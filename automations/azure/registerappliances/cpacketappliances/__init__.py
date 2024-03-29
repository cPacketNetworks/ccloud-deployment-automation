import azure.functions as func
import logging
import json
import requests
import hashlib
import re
import os

import azure.functions as func
import azure.keyvault.secrets
import azure.core.credentials
import azure.identity
import azure.mgmt.compute
import azure.mgmt.subscription
import azure.mgmt.network
import typing

appliance_type_key = "cpacket:ApplianceType"
appliance_type_value = "cClear-V"
key_vault_name = "cpacket"
appliance_username = "cpacket"


def main(event: func.EventGridEvent):
    result = json.dumps(
        {
            "id": event.id,
            "data": event.get_json(),
            "topic": event.topic,
            "subject": event.subject,
            "event_type": event.event_type,
        },
        indent=4,
        sort_keys=True,
    )

    logging.info("%s", result)
    operation_name = event.get_json()["operationName"]

    if operation_name == "Microsoft.Compute/virtualMachineScaleSets/write":
        logging.info(f"handling scaling operation: {operation_name}")
    elif operation_name == "Microsoft.Compute/virtualMachineScaleSets/delete":
        logging.info(f"handling VMSS machine delete: {operation_name}")
    else:
        logging.info(f"ignoring operation: {operation_name}")
        return

    scale_set_name = event.subject.split("/")[-1]
    resource_group_name = event.subject.split("/")[-5]
    logging.info(
        f"scale_set_name: {scale_set_name}, resource_group_name: {resource_group_name}"
    )

    creds = azure.identity.ManagedIdentityCredential()

    subscription_id = get_subscription_id(creds)
    if subscription_id is None:
        return

    compute_client = azure.mgmt.compute.ComputeManagementClient(
        creds, subscription_id=subscription_id
    )
    network_client = azure.mgmt.network.NetworkManagementClient(
        creds, subscription_id=subscription_id
    )

    cvuv_devices = get_cvuv_ip_addresses(
        creds.get_token("https://management.core.windows.net//.default"),
        subscription_id,
        resource_group_name,
        scale_set_name,
    )

    if len(cvuv_devices) == 0:
        logging.info(f"no cVu-Vs found in {scale_set_name}")

    cclearv_ip_address = get_cclearv_ip_address(
        compute_client=compute_client,
        network_client=network_client,
        resource_group_name=resource_group_name,
    )

    logging.info(f"cClear-V IP address: {cclearv_ip_address}")
    registered_cvuv_devices = list_registered_cvuvs(cclearv_ip_address)
    if registered_cvuv_devices is None:
        logging.info(
            "failed to get registered cVu-V IP addresses: skipping synchronization"
        )
        return

    if len(registered_cvuv_devices) == 0:
        logging.info("no existing registered cVu-V IP addresses in cClear-V")
    else:
        logging.info(
            # N.B.: Set() type is not JSON serializable
            f"registered cVu-V devices before synchronization: {json.dumps(list(registered_cvuv_devices), indent=4, sort_keys=True)}"
        )

    cvuv_registry_ips: typing.Dict[str, str] = {
        device["ip"]: device["_id"] for device in registered_cvuv_devices
    }

    # synchronization starts
    successfully_added_cvuv_ips: typing.Set[str] = set()

    for cvuv_ip, cvuv_id, device_id in cvuv_devices:
        if cvuv_ip in cvuv_registry_ips:
            logging.info(f"{cvuv_ip} is already registered with cClear-V")
            successfully_added_cvuv_ips.add(cvuv_ip)
            continue

        logging.info(
            f"registering {cvuv_ip} with {cclearv_ip_address}: {device_id} {cvuv_id}"
        )
        add_remove_cvuv_response = register_cvuv(
            cclearv_ip_address, cvuv_ip, cvuv_id, device_id
        )
        if add_remove_cvuv_response is None:
            logging.info(f"skipping {cvuv_ip} registration due to previous error")
            continue
        else:
            logging.info(f"registered {cvuv_ip}")
            successfully_added_cvuv_ips.add(cvuv_ip)

        auth_result = device_auth(cclearv_ip_address, add_remove_cvuv_response["_id"])
        if auth_result is None:
            logging.info(f"skipping {cvuv_ip} authentication due to previous error")
            continue

        metrics_activation_result = activate_cvuv_metrics(
            cclearv_ip_address, add_remove_cvuv_response["_id"], cvuv_id
        )
        if metrics_activation_result is None:
            logging.info(f"skipping {cvuv_ip} metrics activation due to previous error")
            continue

        configure_influx_result = configure_influx(cvuv_ip, cclearv_ip_address)
        if configure_influx_result is None:
            logging.info(
                f"skipping {cvuv_ip} InfluxDB configuration due to previous error"
            )
            continue

    logging.info(
        f"successfully added cvuv_ips: {','.join(successfully_added_cvuv_ips)}"
    )

    registered_cvuv_ips = set(cvuv_registry_ips.keys())

    for ip in registered_cvuv_ips - successfully_added_cvuv_ips:
        logging.info(f"testing cVu-V {ip}")
        test_response = test_http(f"https://{ip}/")
        if test_response is None:
            try:
                deletion_result = delete_cvuv(cclearv_ip_address, cvuv_registry_ips[ip])
                if deletion_result is None:
                    logging.error(
                        f"failed to remove {ip} with device ID {cvuv_registry_ips[ip]} from {cclearv_ip_address}"
                    )
                else:
                    logging.info(
                        f"successfully removed {ip} with device ID {cvuv_registry_ips[ip]} from {cclearv_ip_address}"
                    )
            except KeyError as e:
                logging.error(f"failed to remove {ip}, no device ID: {e}")
        else:
            logging.info(f"skipping {ip} removal: apparently, it is still alive")


def get_cclearv_ip_address(
    compute_client: azure.mgmt.compute.ComputeManagementClient,
    network_client: azure.mgmt.network.NetworkManagementClient,
    resource_group_name: str,
) -> typing.Optional[str]:
    cclearv_instance = get_vm_by_tag(
        compute_client, appliance_type_key, appliance_type_value, resource_group_name
    )
    if cclearv_instance is None:
        logging.error(
            f"Failed to find cClear-V instance with tag {appliance_type_key}={appliance_type_value}: bailing"
        )
        return

    cclearv_ip_address = get_vm_primary_ip_address(
        cclearv_instance, network_client, resource_group_name
    )

    if cclearv_ip_address is None:
        logging.error(f"failed to get primary IP address for cClear-V instance")
        return

    return cclearv_ip_address


def delete_cvuv(cclearv_ip: str, cvuv_id: str) -> typing.Optional[typing.Dict]:
    cclearv_url = f"https://{cclearv_ip}/rt/data/cvu/delete"
    payload = {
        "_ids": [
            cvuv_id,
        ]
    }
    response = send_prepared_request(
        requests.Request(
            "POST", cclearv_url, json=payload, auth=get_cpacket_credentials()
        ).prepare()
    )
    if response is not None:
        return decode_response(response)
    else:
        logging.error(f"failed removal for {cvuv_id}")
        return None


def activate_cvuv_metrics(
    cclearv_ip: str, device_id: str, device_name: str
) -> typing.Optional[typing.Dict]:
    cclearv_url = f"https://{cclearv_ip}/cvu/metrics_config"
    payload = {
        "device_oid": device_id,
        "device_name": device_name,
        "config": {
            "collect": True,
        },
    }
    response = send_prepared_request(
        requests.Request(
            "POST", cclearv_url, json=payload, auth=get_cpacket_credentials()
        ).prepare()
    )
    if response is not None:
        return decode_response(response)
    else:
        logging.error(f"failed metrics activation for {device_id}")
        return None


def device_auth(cclearv_ip: str, device_id: str) -> typing.Optional[typing.Dict]:
    cclearv_url = f"https://{cclearv_ip}/rt/data/devauth/modify"
    username, password = get_cpacket_credentials()
    payload = {
        "devId": device_id,
        "user": username,
        "pwd": password,
    }
    response = send_prepared_request(
        requests.Request(
            "POST", cclearv_url, json=payload, auth=get_cpacket_credentials()
        ).prepare()
    )
    if response is not None:
        return decode_response(response)
    else:
        logging.error(f"failed device authentication for {device_id}")
        return None


def configure_influx(cvuv_ip: str, cclearv_ip: str) -> typing.Optional[typing.Dict]:
    cvuv_url = f"https://{cvuv_ip}/admin-api/2022/system_settings"
    cclearv_user, cclearv_password = get_cpacket_credentials()
    payload = {
        "stats_db_user": cclearv_user,
        "stats_db_pswd": cclearv_password,
        "stats_db_server": cclearv_ip,
    }
    response = send_prepared_request(
        requests.Request(
            "PATCH", cvuv_url, json=payload, auth=(cclearv_user, cclearv_password)
        ).prepare()
    )
    if response is not None:
        logging.info(f"successfully configured stats DB for {cvuv_ip}")
        return decode_response(response)

    logging.error(f"failed stats DB configuration for {cvuv_ip}")
    return None


def register_cvuv(
    cclearv_ip: str, cvuv_ip: str, cvuv_id: str, device_id: int
) -> typing.Optional[typing.Dict]:
    cclearv_url = f"https://{cclearv_ip}/rt/data/cvu/modify"
    payload = {
        "ip": cvuv_ip,
        "name": cvuv_id,
        "auth_type": "basic",
        "verify_ssl": False,
        "deviceId": device_id,
    }
    logging.info(f"register cVu-V POST payload\n: {json.dumps(payload)}")
    response = send_prepared_request(
        requests.Request(
            "POST", cclearv_url, json=payload, auth=get_cpacket_credentials()
        ).prepare()
    )
    if response is not None:
        logging.info(f"successfully registered {cvuv_ip} with cClear-V")
        return decode_response(response)
    else:
        logging.error(f"failed {cvuv_ip} registration")
        return None


def get_subscription_id(
    credentials: azure.identity.ManagedIdentityCredential,
) -> typing.Optional[str]:
    subscriptions_client = azure.mgmt.subscription.SubscriptionClient(credentials)
    subscriptions = list(subscriptions_client.subscriptions.list())
    if len(subscriptions) == 0:
        logging.error(f"failed to get any subscriptions")
        return None
    elif len(subscriptions) > 1:
        subscription_strings: typing.List[str] = []
        for sub in subscriptions:
            if sub is not None and sub.id is not None:
                subscription_strings.append(sub.id)
        logging.error(
            f"multiple subscriptions obtained when only 1 was expected: {','.join(subscription_strings)}"
        )
        return None

    return subscriptions[0].subscription_id


# https://stackoverflow.com/questions/59613250/get-private-ip-addresses-for-vms-in-a-scale-set-via-python-sdk-no-public-ip-add
def vmss_rest_api_list_nics(
    token: azure.core.credentials.AccessToken,
    subscription_id: str,
    resource_group: str,
    vmss_name: str,
    api_version: str = "2018-10-01",
) -> typing.Optional[typing.Dict]:
    url = f"https://management.azure.com/subscriptions/{subscription_id}/resourceGroups/{resource_group}/providers/microsoft.Compute/virtualMachineScaleSets/{vmss_name}/networkInterfaces"
    params = {"api-version": api_version}
    request = requests.Request("GET", url, params=params)
    prepped = request.prepare()
    prepped.headers["Authorization"] = f"Bearer {token.token}"

    response = send_prepared_request(prepped, verify=True)
    if response is not None:
        return decode_response(response)
    else:
        return None


def list_registered_cvuvs(
    cclearv_ip: str,
) -> typing.Optional[typing.List[typing.Dict]]:
    cclearv_url = f"https://{cclearv_ip}/diag/devices/"  # note trailing slash
    request = requests.Request("GET", cclearv_url, auth=get_cpacket_credentials())
    response = send_prepared_request(request.prepare())
    if response is not None:
        decoded = decode_response(response)
        if decoded is None:
            return None
        else:
            logging.info(f"decoded: {json.dumps(decoded, indent=4, sort_keys=True)}")
            if "cvu" in decoded:
                devices = decoded["cvu"]
                logging.info(
                    f"devices: {json.dumps(devices, indent=4, sort_keys=True)}"
                )
                return devices
            else:
                logging.info("no cVu-V devices found in call to `/diag/devices/`")
                return None
    else:
        return None


def decode_response(response: requests.Response) -> typing.Optional[typing.Dict]:
    try:
        return response.json()
    except requests.exceptions.JSONDecodeError as e:
        logging.error(f"failed to decode JSON for {response.text}: {e}")
        return None


def get_vm_by_tag(
    compute_client: azure.mgmt.compute.ComputeManagementClient,
    tag_name: str,
    tag_value: str,
    resource_group_name: str,
) -> typing.Any:
    virtual_machines = []
    for vm in compute_client.virtual_machines.list(
        resource_group_name=resource_group_name
    ):
        if (
            vm.tags is not None
            and tag_name in vm.tags
            and vm.tags[tag_name] == tag_value
        ):
            virtual_machines.append(vm)

    if len(virtual_machines) == 0:
        logging.info(f"did not find VM with {tag_name}={tag_value}")
        return None

    if len(virtual_machines) > 1:
        logging.error(f"found multiple VMs with {tag_name}={tag_value}")
        return None

    vm = virtual_machines[0]
    logging.info(f"found VM {vm.name} with {tag_name}: {vm.tags[tag_name]}")
    return vm


def get_cpacket_credentials() -> typing.Tuple[str, str]:
    password = os.environ["APPLIANCE_HTTP_BASIC_AUTH_PASSWORD"]
    return (appliance_username, password)


def test_http(url: str) -> typing.Optional[str]:
    logging.info(f"testing existing cVu-V instances: GET {url}")
    prepped = requests.Request("GET", url).prepare()
    response = send_prepared_request(prepped)
    if response is not None:
        return response.text
    else:
        return None


def send_prepared_request(
    prepared: requests.PreparedRequest, verify=False
) -> typing.Optional[requests.Response]:
    with requests.Session() as session:
        response = requests.Response()
        try:
            response = session.send(prepared, timeout=10, verify=verify)
        except requests.exceptions.ConnectionError as e:
            logging.error(f"network error occurred accessing {prepared.url}: {e}")
            return None
        except requests.exceptions.Timeout as e:
            logging.error(f"timeout occurred accessing {prepared.url}: {e}")
            return None
        except requests.exceptions.TooManyRedirects as e:
            logging.error(f"too many redirects occurred accessing {prepared.url}: {e}")
            return None
        except requests.exceptions.HTTPError as e:
            logging.error(f"HTTP error occurred accessing {prepared.url}: {e}")
            return None
        except Exception as e:
            logging.error(
                f"failed to communicate with {prepared.url}, unknown Exception: {e}"
            )
            return None

        if response.status_code >= 200 and response.status_code < 302:
            return response

        err = decode_response(response)
        if err is None:
            return None

        try:
            if "name" in err and "message" in err:
                logging.error(
                    f"HTTP {response.status_code} accessing '{prepared.url}' ({err['name']}): {err['message']}"
                )
        except KeyError:
            logging.error(
                f"HTTP {response.status_code} accessing '{prepared.url}': {response.text}"
            )

        return None


def get_cvuv_ip_addresses(
    token: azure.core.credentials.AccessToken,
    subscription_id: str,
    resource_group_name: str,
    scale_set_name: str,
) -> typing.List[typing.Tuple]:
    scale_set_nics = vmss_rest_api_list_nics(
        token, subscription_id, resource_group_name, scale_set_name
    )
    if scale_set_nics is None:
        logging.error(f"failed to get NICs for {scale_set_name}")
        return []

    cvuv_devices: typing.List[typing.Tuple] = []
    for nic in scale_set_nics["value"]:
        logging.info(f"nic: {nic}")

        if (
            "loadBalancerBackendAddressPools"
            in nic["properties"]["ipConfigurations"][0]["properties"]
        ):
            # This is a cVu-V capture NIC:
            continue

        # Should we also check whether this is a primary IP config or not?

        private_ip_address = nic["properties"]["ipConfigurations"][0]["properties"][
            "privateIPAddress"
        ]

        nic_id = nic["properties"]["virtualMachine"]["id"]
        device_id = nic_id.split("/")[-1]
        cvuv_id = f"cvuv-{hashlib.sha1(nic_id.encode('utf-8')).hexdigest()[0:6]}"
        logging.info(f"Found NIC: {nic_id}: {private_ip_address}")
        cvuv_devices.append((private_ip_address, cvuv_id, device_id))

    return cvuv_devices


def get_vm_primary_ip_address(
    instance: typing.Any, network_client: typing.Any, resource_group: str
) -> typing.Optional[str]:
    primary_nic_id = instance.network_profile.network_interfaces[0].id
    nic_name = primary_nic_id.split("/")[-1]
    nic_info = network_client.network_interfaces.get(resource_group, nic_name)

    if nic_info.ip_configurations is None:
        logging.error(f"failed to get IP configuration for {nic_name}")
        return None

    ip_config = nic_info.ip_configurations[0]
    logging.info(f"ip_config: {ip_config}")

    ip_address = ip_config.private_ip_address
    if ip_address is None:
        logging.error(f"failed to get IP address for {nic_name}")
        return None

    return ip_address

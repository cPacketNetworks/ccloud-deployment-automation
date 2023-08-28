default := all
dockerid := cPacketNetworks
dockerimage := registerappliances
dockerversion := 0.0.2
azurefunction := registerangryhippo
resourcegroup := mbright-bicep-test

.PHONY: all
all: lint format

.PHONY: format
format:
	find applianceregistration -type f -name "*.py" -maxdepth 1 -exec black {} \;

.PHONY: lint
lint:
	shellcheck *.sh 

.PHONY: publish
publish: format
	func azure functionapp publish ${azurefunction}

.PHONY: package
package:
	tar zcf hippo.tar.gz host.json applianceregistration .funcignore requirements.txt

.PHONY: zip
zip:
	zip -r function_app.zip host.json applianceregistration .funcignore requirements.txt .venv

.PHONY: docker-build
docker-build:
	docker build --tag ${dockerid}/${dockerimage}:${dockerversion} .

.PHONY: docker-push
docker-push:
	docker push ${dockerid}/${dockerimage}:${dockerversion}

.PHONY: update-deployment
update-deployment:
	az functionapp config container set --image ${dockerid}/${dockerimage}:${dockerversion} --registry-password something-very-secret --registry-username ${dockerid} --name ${azurefunction} --resource-group ${resourcegroup}

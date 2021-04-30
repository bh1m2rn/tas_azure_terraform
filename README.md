# tas_azure_terraform

The purpose of this script is to quickly deploy a Tanzu Application Service test/sandbox environment on Azure. Ideally, you would have some CI/CD tool that deploys TAS, but the script below can be used in case you don't.

You will need to have the following cli/tools installed to run this script:
1) az
2) terraform
3) uaa (it uses the newer golang based cli https://github.com/cloudfoundry-incubator/uaa-cli)
4) om (https://github.com/pivotal-cf/om)
5) curl
6) jq

How to use:

Simply clone the repo and run the run.sh script, answer a few questions and this script will deploy Opsman, Bosh director and TAS to Azure.

Alternatively, you can use the Docker image which already has all the needed packages:

docker run -it jameslarrea/tanzu:tas_on_azure_v1

Cleaning up:

Since your terraform state file is in the container and TAS is not managed by terraform, the easiest way to delete all resources when you are done testing is to delete the resource group, dns record and service principal.

You can simply run the clean_up.sh script to take care of this for you.
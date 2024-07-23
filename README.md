# Deploy HCP Vault on AWS using Terraform 

1. Create Service Principal w/ the "Contributor" role 
   `https://developer.hashicorp.com/vault/tutorials/terraform-hcp-vault/terraform-hcp-provider-vault#create-a-service-principal-and-key` 
2. Create a SP key pair so TF can authenticate to HCP
3. Add this key pair to the HCP TF provider block or export to terminal
    `export HCP_CLIENT_ID=<client id value previously copied>`
    `export HCP_CLIENT_SECRET=<client secret value previously copied>`
4. Create the HVN, a HashiCorp managed vNet/VPC
5. Create the HCP Vault Cluster
6. Add route and security group to the HVN 

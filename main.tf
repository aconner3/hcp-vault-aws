#=====================
#           provider.tf  
#======================

// Pin the version
terraform {
  required_providers {
    hcp = {
      source = "hashicorp/hcp"
      version = "0.89.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tfe = {
      source = "hashicorp/tfe"
      version = "0.55.0"
    }
      vault = {
        source = "hashicorp/vault"
        version = "4.2.0"
      }
     }
}

# // Configure the HCP provider
provider "hcp" {
  client_id     = ""
  client_secret = ""
  project_id    = ""
}

# // Configure the AWS provider
provider "aws" {
  shared_config_files = [""]
  shared_credentials_files = [""]
  profile = "default"
 }
                  
# // Configure the TFC provider (hashi-demo token) 
provider "tfe" {
  token = ""
}

// Configure Vault provider
provider "vault" {
    address = ""
}

#=================================================
#      Create HCP Service Principal & Key w/ "contributor" perm
#=================================================

resource "hcp_service_principal" "workload_sp" {
  name = "my-app-runtime"
}

resource "hcp_iam_workload_identity_provider" "example" {
  name              = "aws-example"
  service_principal = hcp_service_principal.workload_sp.resource_name
  description       = "Allow my-app on AWS to act as my-app-runtime service principal"

  aws {
    # Only allow workloads from this AWS Account to exchange identity
    account_id = ""
  }

  # Only allow workload's running with the correct AWS IAM Role
  conditional_access = "aws.arn matches `^arn:aws:sts::123456789012:assumed-role/my-app-role`"
}

# #=================================================================
# #                          HVN & Cluster
# #=================================================================
resource "hcp_hvn" "aws-hvn" {
  hvn_id         = "vault-hvn-aws"
  cloud_provider = "aws"
  region         = "us-east-1"
  cidr_block    = "0.0.0.0/25"
}


resource "hcp_vault_cluster" "aws-cluster" {
   hvn_id     = hcp_hvn.aws-hvn.hvn_id
   cluster_id = "vault-cluster-aws"
   tier       = "plus_small"
   public_endpoint = true
   #vault_private_endpoint_url    = "https://test.hashicorp.cloud:8200"
  
  }

# #=================================================================
# #                          Peering 
# #=================================================================
// AWS VPC
resource "aws_vpc" "kingslanding-vpc" {
  cidr_block = "0.0.0.0/16"
}


// Create an HCP network peering to peer your HVN with your AWS VPC. 
// This resource initially returns in a Pending state, because its provider_peering_id is required to complete acceptance of the connection.
resource "hcp_aws_network_peering" "winterfell" {
  peering_id      = "aws-peering"
  hvn_id          = hcp_hvn.aws-hvn.hvn_id
  peer_vpc_id     = aws_vpc.kingslanding-vpc.id
  peer_account_id = aws_vpc.kingslanding-vpc.owner_id
  peer_vpc_region = "us-east-1"
}

// This data source is the same as the resource above, but waits for the connection to be Active before returning.
data "hcp_aws_network_peering" "winterfell" {
  hvn_id                = hcp_hvn.aws-hvn.hvn_id
  peering_id            = hcp_aws_network_peering.winterfell.peering_id
  wait_for_active_state = true
}

// Accept the VPC peering within your AWS account.
resource "aws_vpc_peering_connection_accepter" "peer" {
  vpc_peering_connection_id = hcp_aws_network_peering.winterfell.provider_peering_id
  auto_accept               = true
}

# #=================================================================
# #                          Route Table  
# #=================================================================
resource "hcp_hvn_route" "winterfell" {
  hvn_link         = hcp_hvn.aws-hvn.self_link
  hvn_route_id     = "aws-route"
  destination_cidr = aws_vpc.kingslanding-vpc.cidr_block
  target_link      = data.hcp_aws_network_peering.winterfell.self_link
}

#================================================
#                   OIDC AzureAD Auth 
#================================================
resource "vault_jwt_auth_backend" "example" {
    description         = "Demonstration of the Terraform JWT auth backend"
    path                = "oidc"
    type                = "oidc"
    oidc_discovery_url  = "https://mycompany.auth0.com/"
    oidc_client_id      = "1234567890"
    oidc_client_secret  = "secret123456"
    bound_issuer        = "https://mycompany.auth0.com/"
    tune {
        listing_visibility = "unauth"
    }
}

resource "vault_jwt_auth_backend" "oidc" {
  path = "oidc"
  default_role = "test-role"
}

resource "vault_jwt_auth_backend_role" "example" {
  backend         = vault_jwt_auth_backend.oidc.path
  role_name       = "test-role"
  token_policies  = ["default", "dev", "prod"]

  user_claim            = "https://vault/user"
  role_type             = "oidc"
  allowed_redirect_uris = ["http://localhost:8200/ui/vault/auth/oidc/oidc/callback"]
}



#================================================
#                   TFC Secrets Engine
#================================================
resource "vault_terraform_cloud_secret_backend" "test" {
  backend     = "terraform"
  description = "Manages the Terraform Cloud backend"
  token       = "V0idfhi2iksSDU234ucdbi2nidsi..."

}

// create a role 
resource "vault_terraform_cloud_secret_role" "example" {
  backend      = vault_terraform_cloud_secret_backend.test.backend
  name         = "test-role"
  organization = "example-organization-name"
  team_id      = "team-ieF4isC..."
}

// generate credentials for a role
resource "vault_terraform_cloud_secret_creds" "token" {
  backend = vault_terraform_cloud_secret_backend.test.backend
  role    = vault_terraform_cloud_secret_role.example.name
}

#================================================
#                   Vault TFC Policy 
#================================================
resource "vault_policy" "TFC-User" {
  name = "tfc-user-policy"

  policy = <<EOT
# Access to generate credentials from terraform cloud secrets engine 
path "terraform/creds/user_role" {
  capabilities = ["read"]
}
# Renew a TFC user token lease 
path "sys/leases/renew" {
  capabilities = ["create", "update"]
}

# Lookup a TFC secrets lease
path "sys/leases/lookup/terraform/creds/user_role" {
  capabilities = ["list", "sudo"]
}
EOT
} 



# vault policy write tfc-user -<<EOF
# # Renew TFC secrets lease for noelnn role
# path "" {
#   capabilities = [""]
# }
# path 
# EOF

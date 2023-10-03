
#!/bin/bash

################################################################################
# Author: Ayub, Afrah
# Email: arayub@paloaltonetworks.com
# Code Description:
#   This script helps to automate the process of deploying the Hub-Spoke design
#   of Palo Alto Networks VM-Series NGFWs on Google Cloud. This script requires
#   full read-write-execute access. If you run into permission issues, please 
#   run the below command to update the permissions on the script,
#       chmod 755 setup.sh
#   
#   This script also requires terraform to be installed, version >= 0.15.3, < 2.0
#   is preferred.
#
#   To run this script, simple run the below command in the same directory 
#   where the script is located,
#       ./setup.sh
#
################################################################################

# Uncomment the below line to debug any failures in this script
# set -x

# Function to get and validate the public key path
set_public_key() {

    local key_path
    VARS_FILENAME=$1
    
    echo ""
    echo "You would need an SSH public key to access the VM Instances deployed through this script."
    echo "Would you like to enter the path to your SSH Public Key or Generate a new SSH Key Pair?"
    echo "  (1) Enter the path to SSH Public Key"
    echo "  (2) Generate a new SSH Key Pair"
    echo "  (3) Exit"
    echo ""

    read -p "Enter the number of your choice: " choice

    if [[ $choice == "1" ]]; then
        read -p "Enter the path to your public key file: " key_path

        if [[ -f "$key_path" ]]; then
            public_key_path=$key_path
        else
            echo "Invalid Path. The path entered does not exist. Please try again!"
            exit 1
        fi

    elif [[ $choice == "2" ]]; then
        key_path="${HOME}/.ssh/vmseries-tutorial"
    
        # Generate a new SSH key
        ssh-keygen -f $key_path -t rsa -N '' <<<y >/dev/null 2>&1

        public_key_path="${key_path}.pub"
    else
        echo "Exiting..."
        exit 1
    fi

    echo "Setting public key as: " $public_key_path
    sed -i "s|__ssh_key_name__|$public_key_path|g" $VARS_FILENAME

}

# Function to get the project ID where the resources will be deployed
set_project_id() {

    local project_id
    VARS_FILENAME=$1

    project_ids=($(gcloud projects list --format="value(projectId)"))

    len=${#project_ids[@]}

    if [[ len == 1 ]]; then
        project_id=${project_ids[0]}
    else
        echo ""
        echo "Choose the project where the resources will be deployed"

        for ((i=0; i<${#project_ids[@]}; i++)); do
            echo "($((i+1)))  ${project_ids[i]}"
        done

        read -p "Enter the number of your choice: " choice

        project_id=${project_ids[$((choice-1))]}
    fi
    
    echo "Setting project_id as: " $project_id
    sed -i "s|__project_id__|$project_id|g" $VARS_FILENAME

}

set_region() {
    local region
    VARS_FILENAME=$1

    regions=($(gcloud compute regions list --format="value(NAME)"))

    echo ""
    echo "Choose the region where the resources will be deployed"
    for ((i=0; i<${#regions[@]}; i++)); do
        echo "($((i+1)))  ${regions[i]}"
    done

    read -p "Enter the number of your choice: " choice
    region=${regions[$((choice-1))]}

    echo "Setting region as: " $region
    sed -i "s|__region__|$region|g" $VARS_FILENAME
}

cd $(dirname $0)

# Create a .tfvars from rapid.tfvars.example
cp rapid/rapid.tfvars.example terraform.tfvars

# Set the variables inside .tfvars
set_public_key "terraform.tfvars"
set_project_id "terraform.tfvars"
set_region "terraform.tfvars"


# Initialize and apply the Terraform plan without prompting for confirmation
echo ""
echo "Initializing directory for lab resource deployment"
terraform init

# Deploy resources
echo ""
echo "Deploying Lab Resources required for Hub-Spoke design with Palo Alto Networks VM-Series NGFW on GCP"
terraform apply -auto-approve

if [ $? -eq 0 ]; then
    echo "\nHub-Spoke design with Palo Alto Networks VM-Series NGFW Lab Deployment Completed successfully!"
else
    echo "\nHub-Spoke design with Palo Alto Networks VM-Series NGFW Lab Deployment Failed!"
    exit 1
fi
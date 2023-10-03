
################################################################################
# Author: Viswanathan, Shivaramakrishnan
# Email: shv@paloaltonetworks.com
# Code Description:
#   This script helps to automate the process of destroying all the resources that
#   were deployed by running the setup script. This script requires full 
#   read-write-execute access. If you run into permission issues, please 
#   run the below command to update the permissions on the script,
#       chmod 755 teardown.sh
#   
#   This script also requires terraform to be installed, version >= 0.15.3, < 2.0
#   is preferred.
#
#   To run this script, simple run the below command in the same directory 
#   where the script is located,
#       ./teardown.sh
#
################################################################################

cd $(dirname $0)
cd ..
terraform destroy -auto-approve
rm terraform.tfvars

echo "All resources for this deployment have been deleted."
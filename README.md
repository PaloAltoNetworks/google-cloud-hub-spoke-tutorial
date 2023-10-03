# Secure Google Cloud Hub-and-Spoke with VM-Series

This tutorial shows how to deploy and scale Palo Alto Networks VM-Series Next Generation Firewall with Terraform to secure a hub and spoke architecture in Google Cloud.  The VM-Series enables enterprises to secure their applications, users, and data deployed across Google Cloud and other virtualization environments.  

This tutorial is intended for network administrators, solution architects, and security professionals who are familiar with [Compute Engine](https://cloud.google.com/compute) and [Virtual Private Cloud (VPC) networking](https://cloud.google.com/vpc).


## Architecture

Below is a diagram of the tutorial.  VM-Series firewalls are deployed with a regional managed instance group to secure north/south and east/west traffic for two spoke VPC networks.  

<img src="images/diagram.png">


The VM-Series inspects traffic as follows:

1. Traffic from the internet to applications in the spoke networks are distributed by the External TCP/UDP Load Balancer to the VM-Series untrust interfaces (NIC0). The VM-Series inspects the traffic and forwards permissible traffic through its trust interface (NIC2) to the application in the spoke network.
2. Traffic from the spoke networks destined to the internet is routed to the Internal TCP/UDP Load Balancer in the hub VPC. The VM-Series inspects the traffic and forwards permissible traffic through its untrust interface (NIC0) to the internet.
3. Traffic between spoke networks is routed to the Internal TCP/UDP Load Balancer in the hub VPC. The VM-Series inspects and forwards the traffic through the trust interface (NIC2) into the hub network which routes permissible traffic to the destination spoke network.


## Requirements

The following is required for this tutorial:

1. A Google Cloud project. 
2. A machine with Terraform version:`">= 0.15.3, < 2.0"`

    > [!NOTE]
    > This tutorial assumes you are using Google Cloud Shell. 


### Select a deployment option

This tutorial has two deployment options. Both options deploy identical environments. 

| Option       | Description                                                                                                                                           | 
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Rapid**    | A startup script (`rapid/startup.sh`) quickly builds the environment.  This option is best for those who want to quickly test concepts and use-cases. |
| **Standard** | Best for those who want to modify and apply the Terraform plan to best suit their environment use-cases.                                              |




## Option 1. Rapid deployment

The script, `rapid/setup.sh`, prepares the environment variables and applies the Terraform plan for you.

> [!IMPORTANT]
> This option only supports VM-Series PAYGO Bundle2 (PAN-OS 10.2.2-h2) and does not support bootstrapping to Panorama.

1. Open [Google Cloud Shell](shell.cloud.google.com) <img src="https://storage.googleapis.com/cloud-training/images/devshell.png" alt="cloudshell.png" />.

2. When you are ready to deploy, clone the repository and execute the script to build the cloud resources.

    ```
    git clone https://github.com/PaloAltoNetworks/google-cloud-hub-spoke-tutorial
    ./google-cloud-hub-spoke-tutorial/rapid/setup.sh
    ```

3. Provide the appropriate responses for the scripted prompts. 

4. After all the resources are created, the script displays the following message:

    ```
    Apply complete!

    Outputs:

    EXTERNAL_LB_IP = "35.68.75.133"
    ```

    > The `EXTERNAL_LB_IP` output displays the IP address of the external load balancer’s forwarding rule.  The compute resources may take an additional 10 minutes to complete their bootup process.

4. Proceed to [Access the VM-Series firewall](accessing-the-vm-series-firewall).

    > [!NOTE]
    > You can redisplay the outputs at any time by executing `terraform output` inside the build directory.


## Option 2. Standard deployment

In this deployment option, retrieve the required Terraform files and modify them to deploy the tutorial environment. 

### Prepare for deployment

1. Enable the required APIs, generate an SSH key, and clone the repository. 

    ```
    gcloud services enable compute.googleapis.com
    ssh-keygen -f ~/.ssh/vmseries-tutorial -t rsa
    git clone https://github.com/PaloAltoNetworks/google-cloud-hub-spoke-tutorial
    cd google-cloud-hub-spoke-tutorial
    ```

2. Create a `terraform.tfvars`.

    ```
    cp terraform.tfvars.example terraform.tfvars
    ```

3. Edit the `terraform.tfvars` file and set values for the following variables:

    | Key                     | Value                                                                                | Default                        |
    | ----------------------- | ------------------------------------------------------------------------------------ | ------------------------------ |
    | `project_id`            | The Project ID within Google Cloud.                                                  | `null`                         |
    | `public_key_path`       | The local path of the public key you previously created                              | `~/.ssh/vmseries-tutorial.pub` |
    | `mgmt_allow_ips`        | A list of IPv4 addresses that can have access to the VM-Series management interface. | `["0.0.0.0/0"]`                |
    | `create_spoke_networks` | Set to `false` if you do not want to create the spoke networks.                      | `true`                         |
    | `vmseries_image_name`   | Set to the VM-Series image you want to deploy.                                       | `vmseries-flex-bundle2-1022h2` |

    > [!NOTE]
    > For `vmseries_image_name`, a full list of public images can be found with this command:
    > ```
    > gcloud compute images list \
    >   --project paloaltonetworksgcp-public \
    >   --filter='name ~ .*vmseries-flex.*' \
    >   --format='table(name,PROJECT,status)'
    > ```

4. (Optional) If you are using BYOL image (i.e. `vmseries-flex-byol-*`), the license can be applied during deployment or after deployment.  To bootstrap the license during deployment:
   - [Contact](https://www.paloaltonetworks.com/company/contact-sales) your Palo Alto Networks sales representative to receive the licenses.
   - [Create a Support Account](https://docs.paloaltonetworks.com/vm-series/10-2/vm-series-deployment/license-the-vm-series-firewall/create-a-support-account#id4032767e-a4a8-4f5a-9df2-48f5d63780ba) and [create a deployment profile](https://docs.paloaltonetworks.com/vm-series/10-2/vm-series-deployment/license-the-vm-series-firewall/software-ngfw/create-a-deployment-profile-vm-series).
   - Add the **VM-Series Auth-Code** to `bootstrap_files/authcodes`. 

5. Save your `terraform.tfvars` file.


### (Optional) Bootstrap to Panorama
In production environments, it is highly recommended to use [Panorama](https://docs.paloaltonetworks.com/panorama/10-2/panorama-admin/manage-firewalls) to manage the VM-Series firewalls deployed within the instance group.  

Panorama enables you to seamlessly scale the VM-Series for performance, while managing the firewalls as a single entity.  As new firewalls are deployed, the metadata defined within the instance template automatically bootstraps the firewalls to Panorama.  Then, Panorama licenses and pushes the configuration to the firewalls.


#### Panorama Bootstrap Prerequisites 
* An existing Panorama appliance.
  * If you do not have Panorama deployed, you can deploy Panorama via [Terraform](https://github.com/PaloAltoNetworks/terraform-google-vmseries-modules/tree/main/examples/panorama) or through the [Google Cloud Marketplace](https://www.paloaltonetworks.com/resources/guides/panorama-on-gcp-deployment-guide).
* A baseline configuration for Panorama to successfully bootstrap the VM-Series firewall.  For assistance with this configuration, please see the [Panorama Staging](docs/panorama_staging.md) community guide. 

#### Modify Terraform to Bootstrap to Panorama

1. In `main.tf`, comment/delete the `config/bootstrap.xml` within the `bootstrap` module.  This removes the local firewall configuration from the bootstrap storage bucket.

    <pre>
    module "bootstrap" {
    source          = "PaloAltoNetworks/vmseries-modules/google//modules/bootstrap"
    service_account = module.iam_service_account.email
    location        = "US"
    files = {
        "bootstrap_files/init-cfg.txt"                               = "config/init-cfg.txt"
      <b># "${local_file.bootstrap.filename}"                           = "config/bootstrap.xml"</b>
        "bootstrap_files/content/panupv2-all-contents-8622-7593"     = "content/panupv2-all-contents-8622-7593"
        "bootstrap_files/content/panup-all-antivirus-4222-4735"      = "content/panup-all-antivirus-4222-4735"
        "bootstrap_files/content/panupv3-all-wildfire-703414-706774" = "content/panupv3-all-wildfire-703414-706774"
        "bootstrap_files/authcodes"                                  = "license/authcodes"
    }
    }
    </pre>
   
2. In `bootstrap_files/init-cfg.txt`, specify values to match your Panorama's address, device group, template stack, and VM authorization key. See the [Panorama Staging](docs/panorama_staging.md) community guide for more information. 

    <pre>
    type=dhcp-client
    ip-address=
    default-gateway=
    netmask=
    ipv6-address=
    ipv6-default-gateway=
    dhcp-accept-server-hostname=yes
    dns-primary=169.254.169.254
    dns-secondary=8.8.8.8
    op-command-modes=mgmt-interface-swap
    panorama-server=<b>5.5.5.5</b>
    vm-auth-key=<b>1234123412341234</b>
    dgname=<b>my-panorama-device-group</b>
    tplname=<b>my-panorama-template-stack</b>
    </pre>

3. Proceed to the [Deployment](#deploy) step.

### Deploy

When no further changes are necessary in the configuration, deploy the resources:

1. Initialize and apply the Terraform plan.  

    ```
    terraform init
    terraform apply
    ```

2. After all the resources are created, Terraform displays the following message:

    ```
    Apply complete!

    Outputs:

    EXTERNAL_LB_IP = "35.68.75.133"
    ```

    The `EXTERNAL_LB_IP` output displays the IP address of the external load balancer’s forwarding rule.  The compute resources may take an additional 10 minutes to complete their bootup process.

    > [!NOTE]
    > You can redisplay the outputs at any time by executing `terraform output` inside the build directory.

## Access the VM-Series firewall

To access the VM-Series user interface, a password must be set for the `admin` user.

1. Retrieve the `EXTERNAL_IP` attached to the VM-Series interface.

    ```
    gcloud compute instances list \
        --filter='tags.items=(vmseries-tutorial)' \
        --format='value(EXTERNAL_IP)'
    ```


2. SSH to the VM-Series using the `EXTERNAL_IP` with your private SSH key. 

    ```
    ssh admin@<EXTERNAL_IP> -i ~/.ssh/vmseries-tutorial
    ```

    > [!IMPORTANT]
    > If your login attempt is refused, please wait for the cloud resources to finish booting.

3. On the VM-Series, set a password for the `admin` username. 

    ```
    configure
    set mgt-config users admin password
    ```


4. Commit the changes.
    ```
    commit
    ```


5. Enter `exit` twice to terminate the session.
6. Access the VM-Series web interface using a web browser.  Login with the user `admin`  and the password you configured.

    ```
    https://<EXTERNAL_IP>
    ```

    <img src="images/login.png" width="500">

    

## Internet inbound traffic

Internet traffic is distributed by an external TCP/UDP load balancer to the VM-Series untrust interfaces. The VM-Series inspects and translates the traffic to `VM A` in the `spoke 1` network. `VM A`  runs a generic web service and Jenkins.

<img src="images/diagram_ingress.png">




1. Open a HTTP connection to the web service on `VM A` by copying the `EXTERNAL_LB_IP` value into a web browser.

    ```
    http://<EXTERNAL_LB_IP>
    ```

    <img src="images/ss01.png" width="500">




2. Open a session to the Jenkins service on `VM A` by appending port `8080` to the URL.

    ```
    http://<EXTERNAL_LB_IP>:8080
    ```

    <img src="images/ss02.png" width="500">

    > The request to the Jenkins server fails because the Jenkins application has not been enabled in the VM-Series security policies.  Palo Alto Networks firewalls leverage [App-ID](https://www.paloaltonetworks.com/technologies/app-id)™ to identify and enable applications with layer-7 controls. 


### Safely enabling applications with App-ID™ 

Palo Alto Networks App-ID™ enables you to see applications on your network and learn their behavioral characteristics with their relative risk.  You can use App-ID™ to enable Jenkins traffic through the VM-Series security policies.



1. On the VM-Series, go to **Policies → Security**. Click the allowed applications column within the `inbound-web` security policy. 


    <img src="images/ss03.png" width="1500">


2. Click **ADD** and search for `jenkins`.  Click **OK**.


    <img src="images/ss04.png" width="350">


3. Click **Commit → Commit** to apply the changes to the VM-Series configuration.


    <img src="images/ss05.png" width="1500">


4. Access the Jenkins service again.  The Jenkins page resolves because you enabled the `jenkins` application on the VM-Series security policy.  


    <img src="images/ss06.png" width="500">


5. On the VM-Series, go to **Monitor → Traffic** to view the traffic logs.  Enter the query below to filter for `jenkins` traffic. 

    ```
    ( app eq jenkins )
    ```

    <img src="images/ss07.png" width="1500">



    > The `jenkins` application was denied before the `jenkins` application was added to the **inbound-web** security policy. This is because all Palo Alto Networks firewalls use multiple identification techniques to determine the exact identity of applications traversing your network, including those that try to evade detection by masquerading as legitimate traffic, by hopping ports or by using encryption.


### Internet outbound & east/west traffic 

The VM-Series secures outbound internet traffic from the spoke networks and east-west traffic traversing between spoke networks.  All egress traffic from the spoke networks is routed to an internal TCP/UDP load balancer that distributes traffic to the VM-Series trust interfaces for inspection.


<img src="images/diagram_egress.png">


1. Establish an SSH session with `VM B` in the `Spoke 2` network.  The external load balancer distributes the request to the VM-Series.  The VM-Series inspects and translates the traffic to `VM B`. 

    ```
    ssh paloalto@<EXTERNAL_LB_IP> -i ~/.ssh/vmseries-tutorial
    ```


2. Attempt to download a pseudo malicious file from the internet.  Note, the file is safe and is used for threat prevention testing only.  

    ```
    wget www.eicar.org/download/eicar.com.txt
    ```


3. Generate pseudo malicious traffic between `VM B` and `VM A`.

    ```
    curl http://10.1.0.10/cgi-bin/../../../..//bin/cat%20/etc/passwd

    curl -H 'User-Agent: () { :; }; 123.123.123.123:9999' http://10.1.0.10/cgi-bin/test-critical
    ```


4. On the VM-Series, go to **Monitor → Threat** to view the threat logs.  

    <img src="images/ss08.png" width="1500"> 

    The firewall’s security policies enable you to allow or block traffic on your network based on the user, application, and device.  When traffic matches the allow rule defined in the security policy,  the security profiles that are attached to the rule provide further content inspection.  Security profiles include:

      * [Antivirus](https://docs.paloaltonetworks.com/network-security/security-policy/security-profiles/security-profile-antivirus)
      * [Anti-Spyware](https://docs.paloaltonetworks.com/network-security/security-policy/security-profiles/security-profile-anti-spyware)
      * [Vulnerability Protection](https://docs.paloaltonetworks.com/network-security/security-policy/security-profiles/security-profile-vulnerability-protection)
      * [URL Filtering](https://docs.paloaltonetworks.com/pan-os/10-2/pan-os-admin/url-filtering/url-filtering-overview)
      * [File Blocking](https://docs.paloaltonetworks.com/pan-os/10-2/pan-os-admin/threat-prevention/set-up-file-blocking#idab30127f-3fb2-4a84-99e6-30d7009860fc)
      * [WildFire Analysis](https://docs.paloaltonetworks.com/wildfire/10-2/wildfire-admin/wildfire-overview/about-wildfire) 


## Autoscaling the VM-Series

This tutorial uses a regional managed instance group to deploy and scale VM-Series firewalls across zones within a region.  Autoscaling enables you to scale the security protecting your cloud assets while providing high availability through cross-zone redundancy. 


### Viewing metrics in Cloud Monitoring

The VM-Series firewall can publish native PAN-OS metrics to Google Cloud Monitoring.   Each metric can be set as an autoscaling parameter within the managed instance group.  Custom PAN-OS metrics include: 

* Dataplane CPU utilization
* Dataplane packet buffer utilization
* New connections per second
* Throughput (Kbps)
* Throughput (packets per second)
* Total number of active sessions
* Session utilization
* SSL forward proxy utilization

See [custom PAN-OS metrics published for monitoring](https://docs.paloaltonetworks.com/vm-series/10-2/vm-series-deployment/about-the-vm-series-firewall/custom-pan-os-metrics-published-for-monitoring) for more information. 

The Terraform plan creates a custom Cloud Monitoring dashboard that displays several of the VM-Series metrics.  To view the dashboard, perform the following: 

1. In the Google Cloud console, select **Monitoring → Dashboards**.  
2. Select the dashboard named **VM-Series Metrics**.

### Scaling the VM-Series

The managed instance group created by Terraform sets the minimum and the maximum number of VM-Series replicas to `1`.  

You can modify the minimum and the maximum number of replicas to manually increase the number of running firewalls.

1. Update the Autoscaling replica count through the Google Console or with Terraform. 

   * **Update using Google Cloud Console**
     1. In the Google Cloud console, go to **Compute Engine → Instance Groups**.
     2. Open the `vmseries` instance group and click **EDIT**. 
     3. Within the **Autoscaling** section set:
        *  **Minimum number of instances** to `2`.
        *  **Maximum number of instances** to `3`.
     4. Click **Save**. 
   * **Update using Terraform**

     1. Add the following to your `terraform.tfvars`.

         ```
         vmseries_replica_minimum = 2
         vmseries_replica_maximum = 3
         ```

     2. Re-apply the Terraform plan.  Terraform displays a list of all the resources that will be updated.

         ```
         terraform apply
         ```

     3. At the prompt, enter `yes` to update the cloud resources.
   

2. Go to **Compute Engine → VM instances**.  A new VM-Series instance should be created.

    > [!NOTE]
    > The load balancers will not send traffic to the VM-Series until the bootstrap process has finished.  This process can take up to 10 minutes.  Please see [Bootstrap the VM-Series Firewall](https://docs.paloaltonetworks.com/vm-series/10-2/vm-series-deployment/bootstrap-the-vm-series-firewall) for more information.


3. Once the VM-Series finishes its deployment, follow the [Access the VM-Series firewall](#access-the-vm-series-firewall) instructions to gain access to the firewall’s web interface.  This step is not required if you are bootstrapping the VM-Series to Panorama.  This is because Panorama pushes the entire configuration to the scaled firewalls.
    
    > [!NOTE]
    > The metadata within the instance template associated with the instance group defines how the VM-Series receives its local configuration.

4. On the scaled VM-Series, navigate to **Monitor → Traffic**.  The traffic logs should be populated demonstrating the scaled VM-Series is now processing traffic. 


## Clean up

To avoid incurring charges to your Google Cloud account for the resources you created in this tutorial, delete all the resources when you no longer need them.

1. Run the following command
    ```
    terraform destroy
    ```

2. At the prompt to perform the actions, enter `yes`. 
   
   After all the resources are deleted, Terraform displays the following message:

    ```
    Destroy complete!
    ```

## Additional information

* Learn about the[ VM-Series on Google Cloud](https://docs.paloaltonetworks.com/vm-series/10-2/vm-series-deployment/set-up-the-vm-series-firewall-on-google-cloud-platform/about-the-vm-series-firewall-on-google-cloud-platform).
* Getting started with [Palo Alto Networks PAN-OS](https://docs.paloaltonetworks.com/pan-os). 
* Read about [securing Google Cloud Networks with the VM-Series](https://cloud.google.com/architecture/partners/palo-alto-networks-ngfw).
* Learn about [VM-Series licensing on all platforms](https://docs.paloaltonetworks.com/vm-series/10-2/vm-series-deployment/license-the-vm-series-firewall/vm-series-firewall-licensing.html#id8fea514c-0d85-457f-b53c-d6d6193df07c).
* Use the [VM-Series Terraform modules for Google Cloud](https://registry.terraform.io/modules/PaloAltoNetworks/vmseries-modules/google/latest). 

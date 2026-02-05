## CryoSPARC on Open OnDemand
This repo contains components to install a CryoSPARC interactive app for use with Open OnDemand. CryoSPARC is installed in a single shared Singularity image where the master and worker nodes are on the same node. The interactive app launches a job on a single node and the database and log files are saved to each user's $SCRATCH/.cryosparc-v4.7/ directory. The worker node configuration and randomly assigned port are automatically updated to match each new interactive session. CryoSPARC is accessed using Firefox which is launched on the compute node in the interactive app.

### Requirements
1. Singularity or Apptainer
2. CryoSPARC Academic License ID for the installation.
3. cryosparc_master.tar.gz and cryosparc_worker.tar.gz files downloaded from cryosparc.com into a directory named src located in the same directory as the build_cryosparc4ood.sh script
4. some dynamic form widgets in the form.yml.erb file such as dynamic labels require OOD v4.0.1+
5. installation requires an available GPU and internet access
6. Firefox on compute nodes is required or you can reconfigure how the CryoSPARC GUI is accessed

### Installation
The INSTALL/build_cryosparc4ood.sh script will create a Singularity image which will be used by all users but each user will have their own copy of the database and log files which will be stored in their $SCRATCH directory. Run "build_cryosparc4ood -h" for usage.

### Prerequisites
You will need to review and update any of the following as needed
1. In the template/script.sh file: 
   1. Update the http_proxy variable if your compute nodes do not have internet access.
   2. Update the singularity_image= value to the path of the singulairty image.sif file
   3. Update the user_cryosparc_directory variable if your cluster does not use $SCRATCH
   4. the $TMPDIR is used on the compute node to write the .lock files where are automatically removed when the $TMPDIR is deleted after a job ends
   5. configure the ssdquota and quotamax variables
2. In the INSTALL/build_cryosparc4ood.sh script
   1. update nvidia/cuda version if needed
   2. update the nvidia-driver and nvidia-dkms package versions if needed
   3. remove the --fakeroot singularity option if you do not have it enabled

### Notes
* A new database is installed for each major.minor CryoSPARC version

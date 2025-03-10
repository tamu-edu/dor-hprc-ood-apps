# gpuavail

An Open OnDemand Passenger app that queries the Slurm workload manager configuration to retrieve current GPU node configurations and availability. The app displays the information in two comprehensive tables:

1. Configuration Table: Details the types and numbers of GPUs attached to compute nodes, along with the count of nodes sharing each GPU configuration.

2. Availability Table: Lists GPU compute nodes and resources currently available for new jobs, including the GPU types and counts, CPU cores, and available memory in GB.

The gpuavail script can also be used as a command line utility.

## Installation and Configuration
1. Clone this git repository and copy the gpuavail directory to your installation directory: /var/www/ood/apps/sys/
2. Change ACES to your cluster name on lines 13 and 21 of app.rb
3. Update the url line in the manifest.yml file with your OOD instance.
4. gpuavail app must first be launched by user who has write privileges to the /var/www/ood/apps/sys/gpuavail directory in order to generate the Gemfile.lock file which will be saved in the gpuavail directory.
5. You may have to remove the Gemfile.lock file and regenerate it after updates are made to your system.

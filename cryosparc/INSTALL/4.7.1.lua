help([==[

Description
===========
CryoSPARC is a state of the art scientific software platform for cryo-electron microscopy (cryo-EM) used in research and drug discovery pipelines. 

More information
================
 - Homepage: https://cryosparc.com
 - Use the Cluster Open OnDemand portal to launch the CryoSPARC Interactive App.
 - You will need to apply for an individual academic License ID at https://cryosparc.com/download
 - This module is not needed to run CryoSPARC but does need to be reloaded in a terminal in a CryoSPARC session to use the CLI commands
 - Example CLI commands (quotes and backslashes are required)
     cryosparcm "cli 'get_system_info()'"
     cryosparcm "cli 'get_id_by_email(\"userid@institution.edu\")'"

]==])

whatis([==[Description: This module provides details running CryoSPARC on the Cluster Open OnDemand portal.

       Use the Cluster Open OnDemand portal to launch the CryoSPARC Interactive App.

]==])
whatis([==[Homepage: https://cryosparc.com]==])
whatis([==[URL: https://cryosparc.com]==])

conflict("CryoSPARC")

if not isloaded("WebProxy") then
  load("WebProxy")
end

setenv("SINGULARITYENV_MPLCONFIGDIR", os.getenv("TMPDIR")) 

local user_cryosparc_directory = pathJoin(os.getenv("SCRATCH"), '.cryosparc-v4.7')

-- need to "module reload CryoSPARC" in the terminal of a CryoSPARC session for CLI commands to work
local bashStr = 'eval singularity exec --nv -B ' .. os.getenv("TMPDIR") .. ':/tmp -B /scratch -B ' .. user_cryosparc_directory .. '/cryosparc_master/run:/cryosparc_master/run/ -B ' .. user_cryosparc_directory .. '/cryosparc_database:/cryosparc_database -B ' .. user_cryosparc_directory .. '/cryosparc_cache:/cryosparc_cache -B ' .. user_cryosparc_directory .. '/cryosparc_license:/cryosparc_license /sw/hprc/sw/bio/CryoSPARC/images/cryosparc-v4.7.1.sif cryosparcm "$@"'

-- FIXME cshStr
local cshStr  = "eval `singularity exec --nv /sw/hprc/sw/bio/CryoSPARC/images/cryosparc-v4.7.1.sif cryosparcm $*`"

set_shell_function("cryosparcm",bashStr,cshStr)

if mode() == "load" then
io.stderr:write([==[

       Use the Cluster Open OnDemand portal to launch the CryoSPARC Interactive App.

]==])
end


#!/bin/bash

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
#  title        : simmaker.sh                   #
#  description  : 
#  author       : Dawid Maciazek
#  date         : 2015-01-14
#  version      : 1.0
#  requirements : AWK: GNU Awk 4.0.1
#  bash_version : (developed and tested on)
#               :    4.2.45(1)-release
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

# DEV TO DO
# -- copying scripts from another sim family/ project

# --------------- GLOBAL VARIABLES --------------
# -----------------------------------------------
# Manual string 
HELP="simmaker - simulation scripts and resources manager for lammps
LAMMPS is a classical molecular dynamics code with a number of implemented potentials. 
More information can be found at:
http://lammps.sandia.gov/

How to use:
  * arguments within ? ? are optional path argument, if not specified script will assume current directory.
  Steps to create simulations:

  1) Initialize project: 
  Go to the directory where you want to create project, or give path to this directory as optional argument.
    simmaker -i/--init projectName ?placementDirectory?
      example: cd /tmp; simmaker -i myProject
      or: simmaker -i myProject /tmp

  2) Initialize family directory:
  Go to the project directory, or give path to this directory as optional argument.
    simmaker -f/--family familyName ?projectDirectory?
      example: cd /tmp/myProject; simmaker -f myFamily
      or: simmaker -f myFamily /tmp/myProject

  3) Provide necessary scripts and datafiles.
  Name for given family are listed in file  nameTemplates.txt .
  
  Name convention and location for our example:
  scriptName       |         location           |    purpose
  myFamily.dat     | myProject/myFamily/data    | primary data, used to create subsimulation
  myFamily.in      | myProject/myFamily/scripts | primary input script for lammps
  myFamily.qs      | myProject/myFamily/scripts | primary qsub script 
  myFamily.args    | myProject/myFamily/scripts | list of arguments, passed to awk for each subsimulation number
  myFamily_dat.awk | myProject/myFamily/scripts | awk script for creating datafile for N-th subsimulation
  myFamily_in.awk  | myProject/myFamily/scripts | awk script for creating input script for N-th subsimulation
  myFamily_qs.awk  | myProject/myFamily/scripts | awk script for creating qscript for N-th subsimulation

    Create or copy needed scripts listed above.
    
  4) Create subsimulations (from n to m) for family:
    simmaker -c/--create n-m ?familyDirectory?
      example: cd /tmp/myProject/myFamily; simmaker -c 1-5
      or: simmaker -c 1-5 /tmp/myProject/myFamily

  5) Submitting created subsimulation to queue
    simmaker -qs/--qsub n-m ?familyDirectory?
      example: cd /tmp/myProject/myFamily; simmaker -qs 1-5
      or: simmaker -qs 1-5 /tmp/myProject/myFamily

     
Flags:
  -i  --init      project initialization
  -f  --family    family initialization for given project
  -c  --create    generation sub-simulations for given family
  -qs --qsub      submitting created sub-simulations simulations
  
  -rc --recreate
  -rq --re-qscript

  -p  --post-processing
  -d  --delete
"

# Control dir name
CONTROL_DIR="control"
# Full project log name
PROJECT_LOG="project.log"
# Script directory name
SCRIPT_DIR="scripts"
# Dump directory name
DUMP_DIR="dump"
# Data directory name
DATA_DIR="data"
# Template directory name
TEMPLATE_DIR="nameTemplates.txt"

# Extensions/Affixes/Connectors
DATA_EXT=".dat"
INPUT_EXT=".in"
QSCRIPT_EXT=".qs"
ARGSF_EXT=".args" # additional  arguments file
DUMP_AFFIX=".lammpstrj"
DATA_MOD_AFFIX="_dat.awk"
INPUT_MOD_AFFIX="_in.awk"
QSCRIPT_MOD_AFFIX="_qs.awk"
SIM_NUM_CONNECT="_"

POSTPROCESS_MOD_AFFIX=".sh"

# Awk const variable
INPUT_AWK_V="input"
DATA_AWK_V="data"
DUMP_AWK_V="dump"
ARGS_AWK_V="args"
SUBSIMDIR_AWK_V="simdir"

argv=( $@ )

# ------------------ FUNCTIONS ------------------
# -----------------------------------------------
function warning {
  # ( warning )
  printf "Warning: $1\n" >&2
  return 0
}

function error {
  # ( badCmd )
  printf "Error: invalid command: $1\n\nPass -h or --help as flag for help\n" >&2
  exit 1
}

function generalError {
  # ( errorStr )
  printf "Error: $1\nAborting process\n" >&2
  exit 1
}

# update project log
function updateLog {
# ( familyDir logMsg )
  local familyDir="${1%/}"
  local familyName="${familyDir##*/}"

  local projectLog="${1%/*}/$CONTROL_DIR/$PROJECT_LOG"
  local familyLog="${1%/*}/$CONTROL_DIR/${familyName}.log"
  local logMsg="$2"

  printf "`date '+%a %F %X'`\n Family: $familyName\n$logMsg\n" >> $projectLog 
  printf "`date '+%a %F %X'`\n $logMsg\n" >> $familyLog 
}

# initialize control dir and set up logfiles
function initControlDir {
# ( controlDir )
  local controlDir=$1
  echo "Initializing control directory in project: $controlDir"
  mkdir $controlDir

  # init project log file
  local projectLog="$controlDir/$PROJECT_LOG"

  printf "~~~~~~~~~~~~~~~~~ Project Log ~~~~~~~~~~~~~~~~~~~\n" > $projectLog 
  printf " Location: ${controlDir%/$CONTROL_DIR}\n" >> $projectLog 
  printf " Initialization: `date '+%a %F %X'`\n" >> $projectLog 
  printf " by user: $USER\n" >> $projectLog 
  printf "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n\n" >> $projectLog # init project settings file
  #local Log="$controlDir/$PROJECT_LOG"

  return 0
}

# initialize project
function initProject {
# ( projectName, rootDir ) 
  # trim extra slashes
  local rootDir="${2%/}"
  local projectDir="${2%/}/${1%/}"
  # check if directory exists
  if [[ ! -d $projectDir ]]; then
    echo "Initializing new project in: $rootDir"
    mkdir $projectDir
  else
    generalError "While initializing new project.\nProject directory already exists: $projectDir"
  fi
  # create control directory
  local controlDir="$projectDir/$CONTROL_DIR"
  initControlDir $controlDir

  return 0
}

# create famyly branch
function initFamily {
# ( familyName, projectDir )
  local familyName="${1%/}"
  local projectDir="${2%/}"
  local familyDir="${2%/}/${1%/}"

  if [[ -d $familyDir ]]; then
    generalError "While initializing new family for project.\nFamily directory already exists: $familyDir"
  fi

  local msgLog="Initializing Family: $familyName"
  local scriptDir="${familyDir}/${SCRIPT_DIR}"
  local dumpDir="${familyDir}/${DUMP_DIR}"
  local dataDir="${familyDir}/${DATA_DIR}"

  printf "Initializing new family in: $familyDir\n"
  # init directory structure
  mkdir $familyDir
  mkdir $scriptDir
  mkdir $dumpDir
  mkdir $dataDir

  # init file with name template
  local templateDir="${familyDir}/${TEMPLATE_DIR}"
  printf "~~~ Primary data names ~~~\n" > $templateDir
  printf "input_file:    ${familyName}${INPUT_EXT}\n" >> $templateDir
  printf "data_file:     ${familyName}${DATA_EXT}\n" >> $templateDir
  printf "qScript_file:  ${familyName}${QSCRIPT_EXT}\n" >> $templateDir
  printf "args_file:     ${familyName}${ARGSF_EXT}\n" >> $templateDir
  printf "~~~ Modifying scripts names ~~~\n" >> $templateDir
  printf "input_mod:     ${familyName}${INPUT_MOD_AFFIX}\n" >> $templateDir
  printf "data_mod:      ${familyName}${DATA_MOD_AFFIX}\n" >> $templateDir
  printf "qScript_mod:   ${familyName}${QSCRIPT_MOD_AFFIX}\n" >> $templateDir

  updateLog $familyDir "$msgLog"
}

function setProjectLocalNames {
# ( family Dir )
  familyDir=${1%/}
  projectDir=${familyDir%/*}

  scriptDir="${familyDir}/${SCRIPT_DIR}"
  dumpDir="${familyDir}/${DUMP_DIR}"
  dataDir="${familyDir}/${DATA_DIR}"

  familyName="${familyDir##*/}"
  dataFile="${dataDir}/${familyName}${DATA_EXT}"
  inputScriptFile="${scriptDir}/${familyName}${INPUT_EXT}"
  QScriptFile="${scriptDir}/${familyName}${QSCRIPT_EXT}"
  argsFile="${scriptDir}/${familyName}${ARGSF_EXT}"

  postProcessFile="${scriptDir}${POSTPROCESS_MOD_AFFIX}"

  dataModScriptFile="${scriptDir}/${familyName}${DATA_MOD_AFFIX}"
  inputModScriptFile="${scriptDir}/${familyName}${INPUT_MOD_AFFIX}"
  qScriptModScriptFile="${scriptDir}/${familyName}${QSCRIPT_MOD_AFFIX}"

}

# Check
function checkProjectIntegrity {
# ( projectDir )
  local projectDir=${1%/}
  local controlDir="$projectDir/$CONTROL_DIR"

  # check if directory exists
  if [[ ! -d $projectDir ]]; then
    generalError "Specified project path: $projectDir\n does not exist: $projectDir"
  fi

  # check if control directory exists
  if [[ ! -d $controlDir ]]; then
    generalError "Specified project path: $projectDir\n propably is not correct (missing $CONTROL_DIR file)"
  fi
  echo "DEV: this file is propably project directroy"
  return 0
}



function checkFamilyIntegrity {
# ( familyDir )
  setProjectLocalNames $1
  checkProjectIntegrity $projectDir

  if [[ ! -d $scriptDir ]]; then
    generalError "Specified family path: $familyDir\n propably is no correct (missing ${SCRIPT_DIR})"
  else
    if [[ ! -f $inputScriptFile ]]; then
      generalError "The raw input script is missing, default location and name:\n  $inputScriptFile"; fi
    if [[ ! -f $QScriptFile ]]; then 
      generalError "The raw QScript script is missing, default location and name:\n   $QScriptFile"; fi
    if [[ ! -f $argsFile ]]; then
      generalError "The control arguments file is missing, default location and name:\n   $argsFile"; fi
    if [[ ! -f $dataModScriptFile ]]; then
      generalError "the modifying script for data is missing, default location and name:\n   $dataModScriptFile"; fi
    if [[ ! -f $inputModScriptFile ]]; then
      generalError "The modifying script for input script is missing, default location and name:\n   $inputModScriptFile"; fi
    if [[ ! -f $qScriptModScriptFile ]]; then
      generalError "The modifying script for qscript is missing, default location and name:\n   $qScriptModScriptFile"; fi
    if [[ ! -f $argsFile ]]; then
      generalError "The arguments file is missing, default location and name:\n   $argsFile"; fi
  fi

  if [[ ! -d $dataDir ]]; then
    generalError "Specified family path: $familyDir\n propably is no correct (missing ${DATA_DIR})"
  else
    if [[ ! -f $dataFile ]]; then
      generalError "Missing raw data file, default location and name: \n  $dataFile"; fi
  fi

  if [[ ! -d $dumpDir ]]; then
    generalError "Specified family path: $familyDir\n propably is no correct (missing ${DUMP_DIR})"; fi

  echo "DEV: this file is propably family file"
  return 0 
}

function createInputScript {
# //need: setProjectLocalNames, setSubSimLocalNames
  echo "creating in script: $subSimInputScript "

  awk -f "$inputModScriptFile" -v "$SUBSIMDIR_AWK_V"="$subSimDir" -v "$INPUT_AWK_V"="$subSimInputScript" -v "$DATA_AWK_V"="$subSimDataFile" -v "$DUMP_AWK_V"="$subSimDumpFile" -v "$ARGS_AWK_V"="$subSimArgs" "$inputScriptFile" > "$subSimInputScript" 
}

function createDataScript {
# //need: setProjectLocalNames, setSubSimLocalNames
  echo "creating data : $subSimDataFile"
  awk -f "$dataModScriptFile"  -v "$SUBSIMDIR_AWK_V"="$subSimDir" -v "$INPUT_AWK_V"="$subSimInputScript" -v "$DATA_AWK_V"="$subSimDataFile" -v "$DUMP_AWK_V"="$subSimDumpFile" -v "$ARGS_AWK_V"="$subSimArgs" "$dataFile" > "$subSimDataFile"  
}

function createQScript {
# //need: setProjectLocalNames, setSubSimLocalNames
  echo "creating qscript : $subSimQScript"
  awk -f "$qScriptModScriptFile" -v "$SUBSIMDIR_AWK_V"="$subSimDir" -v "$INPUT_AWK_V"="$subSimInputScript" -v "$DATA_AWK_V"="$subSimDataFile" -v "$DUMP_AWK_V"="$subSimDumpFile" -v "$ARGS_AWK_V"="$subSimArgs" "$QScriptFile" > "$subSimQScript"
}

function setSubSimLocalNames {
# subSimName //need: setProjectLocalNames
  
  subSimNum=$1
  paddedNum=`printf "%04d" $currentNum`
  subSimName="${familyName}${SIM_NUM_CONNECT}${paddedNum}"
  subSimDir="${familyDir}/${subSimName}"
  subSimInputScript="${subSimDir}/${subSimName}${INPUT_EXT}"
  subSimDataFile="${dataDir}/${subSimName}${DATA_EXT}"
  subSimDumpFile="${dumpDir}/${subSimName}${DUMP_AFFIX}"
  subSimQScript="${subSimDir}/${subSimName}${QSCRIPT_EXT}"

  # read argsFile
  local awk_inScript="/^${subSimNum}/{print; exit}"
  subSimArgs="`awk "$awk_inScript" $argsFile`"
  if [[ -z "$subSimArgs" ]]; then
    generalError "Coudnt\'t find record for simulation: $subSimName \n  in file with arguments: $argsFile"
  fi
}

function postprocessing {
  if [[ -n $POSTPROCESS ]]; then
    printf "Post-processing on for simulation: $subSimName\n"
    if [[ -f $postProcessFile ]]; then
      bash $postProcessFile $subSimDir $subSimInputScript $subSimDataFile $subSimQScript
      #                     $1         $2                 $3              $4
    else
      error "Could not find :\n   $postProcessFile\ncreate this file to enable prostprocessing"  
    fi
  fi
}
 

function createScripts {
# ( familyDir createNum )
  setProjectLocalNames $1

  local createNum=$2  
  local startNum=${createNum%-*}
  local endNum=${createNum##*-}
  
  local currentNum=$startNum
  while [ $currentNum -le $endNum ]; do
    setSubSimLocalNames "$currentNum"

    if [[ -d $subSimDir ]]; then
      warning "Subsimulation directory already exists:\n   $sybSim   \nTo recreate simulation with specific number use --recreate flag"  
    else
      mkdir $subSimDir
      createInputScript
      createDataScript
      createQScript
      updateLog $familyDir "Simulation created: $subSimName\nwith arguments: $subSimArgs"
      postprocessing 
    fi
    ((currentNum++))
  done
}

function reCreateScripts {
# ( familyDir createNum )
  setProjectLocalNames $1

  local createNum=$2
  local startNum=${createNum%-*}
  local endNum=${createNum##*-}

  local currentNum=$startNum
  while [ $currentNum -le $endNum ]; do
    setSubSimLocalNames "$currentNum"

    if [[ -d $subSimDir ]]; then
      rm -r $subSimDir
      mkdir $subSimDir
      createInputScript
      createDataScript
      createQScript
      updateLog $familyDir "Simulation recreated: $subSimName\nwith arguments: $subSimArgs"
      postprocessing 
    else
      warning "Subsimulation directory does not exists:\n   $sybSim   \nCreating"  
      mkdir $subSimDir
      createInputScript
      createDataScript
      createQScript
      updateLog $familyDir "Simulation created: $subSimName\nwith arguments: $subSimArgs"
      postprocessing 
    fi
    ((currentNum++))
  done
}

function reCreateQscript {
# ( familyDir createNum )
  setProjectLocalNames $1

  local createNum=$2
  local startNum=${createNum%-*}
  local endNum=${createNum##*-}

  local currentNum=$startNum
  while [ $currentNum -le $endNum ]; do
    setSubSimLocalNames "$currentNum"

    if [[ -d $subSimDir ]]; then
      rm $subSimQScript
      createQScript
      updateLog $familyDir "Simulation qScript recreated: $subSimName\nwith arguments: $subSimArgs"
    else
      warning "Subsimulation directory does not exists:\n   $sybSim   \nUse --create flag to create file"  
    fi
    
    ((currentNum++))
  done
}

function createTemplate {
# ( familyDir )
  setProjectLocalNames $1
  printf "Creating template scripts\n"
  updateLog $familyDir "Initializing template scripts set"

  if [[ ! -f $dataFile ]]; then
    > $dataFile; fi
  if [[ ! -f  $inputScriptFile ]]; then
    > $inputScriptFile; fi
  if [[ ! -f  $QScriptFile ]]; then
    > $QScriptFile; fi
  if [[ ! -f  $argsFile ]]; then
    > $argsFile; fi

  if [[ ! -f $dataModScriptFile ]]; then
    > $dataModScriptFile; fi
  if [[ ! -f  $inputModScriptFile ]]; then
    > $inputModScriptFile; fi
  if [[ ! -f  $qScriptModScriptFile ]]; then
    > $qScriptModScriptFile; fi
}

function qsubScripts {
# ( familyDir qsubNum )
  setProjectLocalNames $1

  local createNum=$2
  local startNum=${createNum%-*}
  local endNum=${createNum##*-}

  local currentNum=$startNum
  while [ $currentNum -le $endNum ]; do
    local paddedNum=`printf "%04d" $currentNum`
    setSubSimLocalNames "${currentNum}"
    if [[ ! -d $subSimDir ]]; then
      warning "Subsimulation directory does not exist:\n   $sybSim\nTo create subsimulation use --create flag"  
    else
      ( cd $subSimDir; qsub $subSimQScript )
      updateLog $familyDir "Simulation started: $subSimName"
    fi
    ((currentNum++))
  done
}
 

# ------------------------------------
# --------- SCRIPT MAIN BODY ---------
# ------------------------------------

# --------- CHECK CML ARG ------------
if [[ $# -eq 0 ]] ; then
  printf "$HELP\n" 
  exit 0
fi

i=0
while [[ $i -lt $# ]] ; do
  #${argv[$i]} 

  # Help
  if [[ "${argv[$i]}" = "-h" ]] || [[ "${argv[$i]}" = "--help" ]] ; then
    printf "$HELP"
    exit 0
  fi

  # Initialize simulation project
  if [[ "${argv[$i]}" = "-i" ]] || [[ "${argv[$i]}" = "--init" ]] ; then
    ((i++))
    if [[ -n $INIT ]]; then
      error "Repeated Command: --init"; fi
    if [[ -z ${argv[$i]} ]]; then
      error "Project name is not specified"; fi

    INIT="${argv[$i]}"
    ((i++))
    if [[ -n ${argv[$i]} ]]; then
      if [[ ${argv[$i]} =~ ^- ]]; then
        warning "Project Directory is not given (or incorrect), setting current directory"
        INITDIR=`pwd`
      else
        INITDIR="${argv[$i]}"
      fi
    else
      warning "Project Directory is not given, setting current directory"
      INITDIR=`pwd`
    fi

    ((i++)); continue
  fi

  # Initialize simulation family
  if [[ "${argv[$i]}" = "-f" ]] || [[ "${argv[$i]}" = "--family" ]] ; then
    ((i++))
    if [[ -n $FAMILY ]]; then
      error "Repeated Command: --family"; fi
    if [[ -z ${argv[$i]} ]]; then
      error "Family name is not specified"; fi

    FAMILY="${argv[$i]}"
    ((i++))
    if [[ -n ${argv[$i]} ]]; then
      if [[ ${argv[$i]} =~ ^- ]]; then
        warning "Project Directory is not given (or incorrect), setting current directory"
        PRODIR=`pwd`
      else
        PRODIR="${argv[$i]}"
      fi
    else
      warning "Project Directory is not given, setting current directory"
      PRODIR=`pwd`
    fi

    ((i++)); continue
  fi

  # create (N / x-y / x-) simulations
  if [[ "${argv[$i]}" = "-c" ]] || [[ "${argv[$i]}" = "--create" ]] ; then
    ((i++))
    if [[ -n $CREATE ]]; then
      error "Repeated Command: --create"; fi
    if [[ -z "${argv[$i]}" ]]; then
      error "Simulation number to create is not specified"; fi
    if [[ ! "${argv[$i]}" =~ ^[0-9]+-[0-9]+$ ]]; then
      error  "Unsigned integer-integer expected (eg. 0-33), received: ${argv[$i]}"; fi

    CREATE=${argv[$i]}
    if [[ ${CREATE%-*} -gt ${CREATE##*-} ]]; then
      error  "Unsigned integer-integer expected (in ascending order!), received: ${argv[$i]}"; fi
    ((i++))

    if [[ -n ${argv[$i]} ]]; then
      if [[ ${argv[$i]} =~ ^- ]]; then
        warning "Family directory is not given (or incorrect), setting current directory"
        FAMILYDIR=`pwd`
        ((i--))
      else
        FAMILYDIR="${argv[$i]}"
      fi
    else
      warning "Family directory is not given, setting current directory"
      FAMILYDIR=`pwd`
    fi
    ((i++)); continue
  fi

  # recreate (N / x-y) simulations
  if [[ "${argv[$i]}" = "-rc" ]] || [[ "${argv[$i]}" = "--recreate" ]] ; then
    ((i++))
    if [[ -n $RECREATE ]]; then
      error "Repeated Command: --recreate"; fi
    if [[ -z "${argv[$i]}" ]]; then
      error "Simulation number to recreate is not specified"; fi
    if [[ ! "${argv[$i]}" =~ ^[0-9]+-[0-9]+$ ]]; then
      error  "Unsigned integer-integer expected (eg. 0-33), received: ${argv[$i]}"; fi

    RECREATE=${argv[$i]}
    if [[ ${RECREATE%-*} -gt ${RECREATE##*-} ]]; then
      error  "Unsigned integer-integer expected (in ascending order!), received: ${argv[$i]}"; fi
    ((i++))

    if [[ -n ${argv[$i]} ]]; then
      if [[ ${argv[$i]} =~ ^- ]]; then
        warning "Family directory is not given (or incorrect), setting current directory"
        FAMILYDIR=`pwd`
        ((i--))
      else
        FAMILYDIR="${argv[$i]}"
      fi
    else
      warning "Family directory is not given, setting current directory"
      FAMILYDIR=`pwd`
    fi
    ((i++)); continue
  fi

  # re create qscript
  if [[ "${argv[$i]}" = "-rq" ]] || [[ "${argv[$i]}" = "--re-qscript" ]] ; then
    ((i++))
    if [[ -n $REQSCRIPT ]]; then
      error "Repeated Command: --re-qscript"; fi
    if [[ -z "${argv[$i]}" ]]; then
      error "Simulation number to recreate qscript is not specified"; fi
    if [[ ! "${argv[$i]}" =~ ^[0-9]+-[0-9]+$ ]]; then
      error  "Unsigned integer-integer expected (eg. 0-33), received: ${argv[$i]}"; fi

    REQSCRIPT=${argv[$i]}
    if [[ ${REQSCRIPT%-*} -ge ${REQSCRIPT##*-} ]]; then
      error  "Unsigned integer-integer expected (in ascending order!), received: ${argv[$i]}"; fi
    ((i++))

    if [[ -n ${argv[$i]} ]]; then
      if [[ ${argv[$i]} =~ ^- ]]; then
        warning "Family directory is not given (or incorrect), setting current directory"
        FAMILYDIR=`pwd`
        ((i--))
      else
        FAMILYDIR="${argv[$i]}"
      fi
    else
      warning "Family directory is not given, setting current directory"
      FAMILYDIR=`pwd`
    fi
    ((i++)); continue
  fi

  # qsub simulation
  if [[ "${argv[$i]}" = "-qs" ]] || [[ "${argv[$i]}" = "--qsub" ]] ; then
    ((i++))
    if [[ -n $QSUB ]]; then
      error "Repeated Command: --qsub"; fi
    if [[ -z ${argv[$i]} ]]; then
      error "Simulation number to test is not specified"; fi
    if [[ ! "${argv[$i]}" =~ ^[0-9]+-[0-9]+$ ]]; then
      error  "Unsigned integer-integer expected (eg. 0-33), received: ${argv[$i]}"; fi

    QSUB="${argv[$i]}"
    if [[ ${QSUB%-*} -ge ${QSUB##*-} ]]; then
      error  "Unsigned integer-integer expected (in ascending order!), received: ${argv[$i]}"; fi

    ((i++))
    if [[ -n ${argv[$i]} ]]; then
      if [[ ${argv[$i]} =~ ^- ]]; then
        warning "Family directory is not given (or incorrect), setting current directory"
        FAMILYDIR=`pwd`
        ((i--))
      else
        FAMILYDIR="${argv[$i]}"
      fi
    else
      warning "Family directory is not given, setting current directory"
      FAMILYDIR=`pwd`
    fi
    ((i++)); continue
  fi


  # create template scripts
  if [[ "${argv[$i]}" = "-t" ]] || [[ "${argv[$i]}" = "--template" ]] ; then
    ((i++))
    if [[ -n $QSUB ]]; then
      error "Repeated Command: --template"; fi

    TEMPLATE="yes"
    ((i++))
    if [[ -n ${argv[$i]} ]]; then
      if [[ ${argv[$i]} =~ ^- ]]; then
        warning "Family directory is not given (or incorrect), setting current directory"
        FAMILYDIR=`pwd`
        ((i--))
      else
        FAMILYDIR="${argv[$i]}"
      fi
    else
      warning "Family directory is not given, setting current directory"
      FAMILYDIR=`pwd`
    fi

    ((i++)); continue
  fi
 
  # Post-processing 
  if [[ "${argv[$i]}" = "-p" ]] || [[ "${argv[$i]}" = "--post-processing" ]] ; then
    ((i++))
    if [[ -n $POSTPROCESS ]]; then
      error "Repeated Command: --template"; fi

    POSTPROCESS="yes"
    ((i++))
    if [[ -n ${argv[$i]} ]]; then
      if [[ ${argv[$i]} =~ ^- ]]; then
        warning "Family directory is not given (or incorrect), setting current directory"
        FAMILYDIR=`pwd`
        ((i--))
      else
        FAMILYDIR="${argv[$i]}"
      fi
    else
      warning "Family directory is not given, setting current directory"
      FAMILYDIR=`pwd`
    fi

    ((i++)); continue
  fi



  # UNFLAGGED OPTION // UN USE
  echo "Developer warning --- unflaged option possible"
  if [[ `echo ${argv[$i]} | grep '^-.*'`  ]] ; then
    error "Unknow flag ${argv[$i]}"
  else
    if [[ -z $SIM ]]; then
      echo "refeting to simulation $SIM"
      SIM="${argv[$i]}"
    else
      error "Repeated Command"
    fi

    ((i++)); continue
  fi

done 

# ----------- EXECUTE ------------

# Initialize project and exit
if [[ -n $INIT ]] ; then
  initProject $INIT $INITDIR
  exit 0
fi


# Initialize family in project and exit
if [[ -n $FAMILY ]] ; then
  initFamily $FAMILY $PRODIR
  exit 0
fi

# Create simulations
if [[ -n $CREATE ]]; then
  checkFamilyIntegrity $FAMILYDIR
  createScripts $FAMILYDIR $CREATE
fi

if [[ -n $RECREATE ]]; then
  checkFamilyIntegrity $FAMILYDIR
  reCreateScripts $FAMILYDIR $RECREATE
fi

if [[ -n $REQSCRIPT ]]; then
  checkFamilyIntegrity $FAMILYDIR
  reCreateQscript $FAMILYDIR $REQSCRIPT
fi

if [[ -n $TEMPLATE ]]; then
  setProjectLocalNames $FAMILYDIR
  checkProjectIntegrity $projectDir
  createTemplate $FAMILYDIR
fi

if [[ -n $QSUB ]]; then
  checkProjectIntegrity $projectDir
  qsubScripts $FAMILYDIR $QSUB
fi

exit 0

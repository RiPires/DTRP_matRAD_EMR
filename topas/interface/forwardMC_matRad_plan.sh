#!/usr/bin/env bash

set -e

my_name=`echo "$0" |sed 's,.*[\\/],,'`
if test $# -lt 1; then
    cat >&2 <<EOF

Usage: $my_name matRad_workspace

$my_name compute forward-MC dose distribution

Options:
  --threads                     number of threads [default: 0 (all threads)]
  --label                       label, [default: "matrad_plan"]
  --minRelWeight                minimum relative weight of resultGUI.w to be considered [default: 0.001]
  --fracHistories               fraction of total particle histories to be simulated [default: 0.0001]
  --productionCut               production cut in mm [default: 0.5]
EOF
    exit 1
fi

export MC_PBS=1
export MC_FRAC_HISTORIES=0.0001
export MC_MINRELWEIGHT=0.001
export MC_PRODUCTION_CUT_MM=0.5
nbThreads=28
batch=''
memory=32000
workspace=`realpath $1`
filename=${workspace##*/}
ROOT=`dirname $workspace` 
shift 

while test $# -gt 0; do

    case "$1" in
      --threads) shift && nbThreads=`echo $1` ;;
        --batch) shift && batch=`echo $1` ;;
       --runMem) shift && memory=`echo $1` ;;
        --label) shift && export MC_SIM_LABEL=`echo $1` ;;
 --minRelWeight) shift && export MC_MINRELWEIGHT=`echo $1` ;;
--fracHistories) shift && export MC_FRAC_HISTORIES=`echo $1` ;;
--productionCut) shift && export MC_PRODUCTION_CUT_MM=`echo $1` ;;
              *) # concatenate everything else to other_args
                # and hope that the user knows what they are doing.
               cat >&2 <<EOF
Error. Option $1 not supported.
Exiting...
EOF
               exit 1
               ;;

    esac
    shift

done

if hash topas 2>/dev/null; then
  echo "Using TOPAS for forward MC simulation"
else
  echo "TOPAS not in the environment path"
  echo "Exiting..."
  exit 1
fi

# Create directory to hold data
data_dir="${ROOT}/data_PID$$_${filename%.*}"
mkdir -p ${data_dir}
cd ${data_dir}

# Flush options
echo
echo "----------> PID $$ `date` Options"   | tee log
echo "    workspace: $filename"            | tee -a log
echo "      threads: $nbThreads"           | tee -a log
echo " minRelWeight: $MC_MINRELWEIGHT"     | tee -a log
echo "fracHistories: $MC_FRAC_HISTORIES"   | tee -a log
echo "productionCut: $MC_PRODUCTION_CUT_MM"| tee -a log
#echo "    batch: $batch"                 | tee -a log
#echo "   runMem: $memory"                | tee -a log
#echo "      PBS: $MC_PBS"                | tee -a log

# Prepare MC simulation
echo
echo "----------> PID $$ `date` Preparing fMC files" | tee -a log
prepare_MCsimulation.sh ${workspace} | tee -a log
sleep 1

# Submit jobs
echo
echo "----------> PID $$ `date` Submitting jobs" | tee -a log
if test "x${batch}" = x; then
    submit_all_forwardMC.sh --threads $nbThreads | tee -a log
else
    submit_all_forwardMC.sh --threads $nbThreads --batch $batch --runMem $memory | tee -a log
fi
sleep 1

echo
nbJobs=`find . -name "forwardMC_*run?.txt" | wc -l`
echo "----------> PID $$ `date` Total number of jobs: $nbJobs" | tee -a log
sleep 1

echo
while ((`tail forwardMC*log 2>/dev/null | grep Elapsed\ times | wc -l` < $nbJobs))
do
  echo -ne "----------> `date` Waiting for fMC results\\r"
  sleep 1
done
sleep 1

# Import results
echo
echo "----------> PID $$ `date` Importing fMC results" | tee -a log
calc_stats_TOPAS.py -i MCparam.mat | tee -a log
if test -e MCdata.mat
then
  import_forwardMC_results.sh --matrad ${workspace} --topas MCdata.mat | tee -a log
fi
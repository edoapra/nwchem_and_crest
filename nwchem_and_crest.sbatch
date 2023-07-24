#!/bin/bash
#SBATCH -N 1
#SBATCH --ntasks-per-node 36
#SBATCH -t 23:59:00
#SBATCH -A scicons
#SBATCH -o nwandcr.output.%j
#SBATCH -e nwandcr.output.%j
#SBATCH -J nwcr
#SBATCH --export ALL
#SBATCH --mail-type=FAIL,END
#SBATCH --mail-user edo@emsl.pnl.gov

source /etc/profile.d/modules.sh
set -ev
module purge
module load gcc/9.3.0
#module load python/3.8.1
module  load openmpi
mymolecule=cyclopentane
rm -f $mymolecule.xyz $mymolecule.smi
cat > cyclopentane.smi <<EOF
C1CCCC1
EOF
cat > ethane.smi <<EOF
CC
EOF
cat > propane.smi <<EOF
CCC
EOF
orgpwd=$(pwd)
BASEDIR=/tmp
MYTMPDIR=$BASEDIR/$(id -n -u)_conda
MYPREFIX=$BASEDIR/$(id -n -u)_miniconda3
mkdir -p $MYTMPDIR
cd $MYTMPDIR
rm -rf $MYPREFIX || true
mkdir -p $MYPREFIX
MYINSTALL=Miniconda3-py38_23.1.0-1-Linux-x86_64.sh
rm -f $MYINSTALL
wget https://repo.anaconda.com/miniconda/$MYINSTALL
bash $MYINSTALL -u -b -p $MYPREFIX
eval "$($MYPREFIX/bin/conda shell.bash hook)"
conda install -c conda-forge -y micromamba
eval "$(micromamba shell hook --shell=bash)"
micromamba activate $MYPREFIX
micromamba install -c conda-forge -y crest openbabel
cd $orgpwd
crestdir=$orgpwd/crest_$mymolecule
rm -rf $crestdir
mkdir -p $crestdir
which crest
obabel -i smi $mymolecule.smi -o xyz  -O $mymolecule.xyz -h --gen3d 
cp $mymolecule.xyz $crestdir/.
cd $crestdir
ls -l
cat "$mymolecule.xyz"
/usr/bin/time -p crest  "$mymolecule.xyz" -T 8
IMGNAME=/big_scratch/./nwchems_`id -u`.img
export APPTAINER_CACHEDIR=`pwd`/cache
export https_proxy=http://proxy.emsl.pnl.gov:3128
singularity pull -F --name $IMGNAME oras://ghcr.io/edoapra/nwchem-singularity/nwchem-dev.ompi41x:latest
export APPTAINERENV_SCRATCH_DIR=/dev/shm
export APPTAINERENV_OMP_NUM_THREADS=1
export APPTAINERENV_PERMANENT_DIR=/big_scratch
no_crestconf=$(wc -l crest.energies |cut -d " " -f 1)
max_conf=$(( $no_crestconf < 20 ? $no_crestconf : 20 ))
echo max_conf is $max_conf
cd ..
rm -f ${mymolecule}_tab.txt || true
nn=1
while [  $nn -le $max_conf ]; do
    echo The counter is $nn
    confname=${mymolecule}_crest_conf${nn}
    conf_input=${confname}.nw
    conf_output=${confname}.output
    rm -f $conf_input $conf_output
    cat top >> $conf_input
    echo load $crestdir/crest_conformers.xyz frame ${nn} >> $conf_input
    cat bot >> $conf_input
    srun -n $SLURM_NPROCS  singularity exec $IMGNAME nwchem  $conf_input >& $conf_output
    echo "Conformer" $nn ":" $(grep l\ DF $conf_output |tail -1)  >> ${mymolecule}_tab.txt
    let nn=nn+1
done
#cat ${mymolecule}_tab.txt
sort -r -t " " -k 8 < sort -r -t " " -k 8  ${mymolecule}_tab.txt

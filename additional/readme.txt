Hi,
all scripts can be run without parameters, a Help will be shown..


INSTALLATION
Make sure your ssh private file is installed in your ~/.ssh folder.
You just have to do this:
cp /scratch/work/project/open-11-37/.ssh/key_it4s1 ~/.ssh/.
chmod 600 ~/.ssh/key_it4s1

BEWARE! According to ISCE JPL licence, the processing can be done ONLY by an
employee of IT4Innovations! So.. e.g. by Vaclav Svaton that has this ssh key installed..


SETUP ENVIRONMENT
Run following commands (either on login or processing node)

source /scratch/work/project/open-11-37/bashrc
          (it will load modules, set the paths etc)
isceserver "sw/test"
          (it will test the internet connection - should write that it works.)



RUN A PROCESSING
Just run..
it4s1_process_all.sh
      - a help will come out. Perhaps you don't need anything else, just choose an area, try with radius 7 (km). Very small radiuses (<2 km) can end in a bug, too big may not finish in one hour
(run it in your processing directory. It will create "temp" and "output" dirs. The script will guide you..)


SEE RESULTS
The results are CSV files in directory "output" created in the folder you start the script from.
You can load these CSV e.g. in QGIS: Layer -> Add Layer -> Add Delimited Text Layer

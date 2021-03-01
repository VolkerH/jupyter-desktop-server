FROM jupyter/base-notebook:python-3.8.5


USER root

RUN apt-get -y update \
 && apt-get install -y dbus-x11 \
   firefox \
   xfce4 \
   xfce4-panel \
   xfce4-session \
   xfce4-settings \
   xorg \
   xubuntu-icon-theme \
   git

# Remove light-locker to prevent screen lock
RUN wget 'https://sourceforge.net/projects/turbovnc/files/2.2.5/turbovnc_2.2.5_amd64.deb/download' -O turbovnc_2.2.5_amd64.deb && \
   apt-get install -y -q ./turbovnc_2.2.5_amd64.deb && \
   apt-get remove -y -q light-locker && \
   rm ./turbovnc_2.2.5_amd64.deb && \
   ln -s /opt/TurboVNC/bin/* /usr/local/bin/

RUN apt-get install -y libqt5x11extras5-dev ssh

# apt-get may result in root-owned directories/files under $HOME
RUN chown -R $NB_UID:$NB_GID $HOME

ADD . /opt/install
RUN fix-permissions /opt/install


USER $NB_USER
# this installs the conda environment needed for jupyter-desktop-server
# I added napari to this
RUN cd /opt/install && \
   conda env update -n base --file environment.yml 

# SpaceM requirements are in conflict with the requirements for
# jupyter-server. Trying to install both into the same environment
# broke the desktop server in my experiments.

# initial attempt
#RUN cd /opt/install/spacem &&  \
#   conda env create -f ../spacem.yml

# this is using the spaceM setup from Andreas's Dockerfile
WORKDIR /opt/install spacem

RUN --mount=type=cache,id=custom-conda,target=/opt/conda/pkgs \
# Create conda environment.
    source /opt/conda/etc/profile.d/conda.sh \
    && conda create --yes --name spacem python=3.8

# Instruct docker buildkit to cache pip package downloads for repeated builds.
RUN --mount=type=cache,id=custom-pip,target=/root/.cache/pip \
# First install minimal version of torch to avoid pip installing full 1.4GB version.
    conda run --name spacem python -m \
    pip install torch==1.7.1+cpu -f https://download.pytorch.org/whl/torch_stable.html \
# Then install all remaining Python packages. Compile to space-saving byte-code instead of keeping source code.
    && conda run --name spacem python -m \
    pip install --compile -r /opt/install/spacem/requirements.txt -r /opt/install/spacem/dev_requirements.txt \
# Finally cleanup after a Conda install
    && conda clean --all --force-pkgs-dirs --yes \
    && find /opt/conda/ -follow -type f -name '*.a' -delete \
    && find /opt/conda/ -follow -type f -name '*.pyc' -delete

RUN  cd /opt/install/spacem && conda run --name spacem python -m \
     pip install -e .

# Trigger initial Cellpose model download to cache models.
RUN --mount=type=cache,id=custom-cellpose,target=$HOME/.cellpose \
    conda run -n spacem python -c "import cellpose.models"

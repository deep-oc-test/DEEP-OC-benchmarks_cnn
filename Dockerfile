# Dockerfile may have following Arguments: tag, pyVer, branch, jlab
# tag - tag for the Base image, (e.g. 1.10.0-py3 for tensorflow)
# branch - user repository branch to clone (default: master, other option: test)
# flavor - becnhmark flavor ('synthetic', 'dataset', 'pro')
# jlab - if to insall JupyterLab (true) or not (false, default)
#
# To build the image:
# $ docker build -t <dockerhub_user>/<dockerhub_repo> --build-arg arg=value .
# or using default args:
# $ docker build -t <dockerhub_user>/<dockerhub_repo> .
#
# Be Aware! For the Jenkins CI/CD pipeline, 
# input args are defined inside the Jenkinsfile, not here!
#

# ARG tag=1.10.0-py36
# ARG image=deephdc/tensorflow

ARG tag=1.14.0-gpu-py3
ARG image=tensorflow/tensorflow

# Base image, e.g. tensorflow/tensorflow:1.14.0-py3
FROM ${image}:${tag}

LABEL maintainer='A.Grupp, V.Kozlov (KIT)'
LABEL version='0.5.0'
# tf_cnn_benchmarks packed with DEEPaaS API

# renew 'image' and 'tag' to access during the build
ARG image
ARG tag

# What user branch to clone [!]
ARG branch=master

# What benchmark flavor to use
ARG flavor=synthetic

# If to install JupyterLab
ARG jlab=true

# Oneclient version, has to match OneData Provider and Linux version
ARG oneclient_ver=19.02.0.rc2-1~bionic

# Install ubuntu updates and python related stuff
# link python3 to python, pip3 to pip, if needed
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y --no-install-recommends \
         git \
         curl \
         wget \
         python3-setuptools \
         python3-dev \
         python3-pip \
         python3-wheel && \ 
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /root/.cache/pip/* && \
    rm -rf /tmp/* && \
    python3 --version && \
    pip3 --version


# Set LANG environment
ENV LANG C.UTF-8

# Set the working directory
WORKDIR /srv

# Install rclone
RUN wget https://downloads.rclone.org/rclone-current-linux-amd64.deb && \
    dpkg -i rclone-current-linux-amd64.deb && \
    apt install -f && \
    mkdir /srv/.rclone/ && touch /srv/.rclone/rclone.conf && \
    rm rclone-current-linux-amd64.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /root/.cache/pip/* && \
    rm -rf /tmp/*

# INSTALL oneclient for ONEDATA
RUN curl -sS  http://get.onedata.org/oneclient-1902.sh | bash -s -- oneclient="$oneclient_ver" && \
    apt-get clean && \
    mkdir -p /mnt/onedata && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/*

# Install DEEPaaS from PyPi
# Install FLAAT (FLAsk support for handling Access Tokens)
RUN pip3 install --no-cache-dir \
         'deepaas>=1.3.0' \
         flaat>=0.5.3 && \
    rm -rf /root/.cache/pip/* && \
    rm -rf /tmp/*

# Disable FLAAT authentication by default
ENV DISABLE_AUTHENTICATION_AND_ASSUME_AUTHENTICATED_USER yes

# Install JupyterLab
ENV JUPYTER_CONFIG_DIR /srv/.deep-start/
# Necessary for the Jupyter Lab terminal
ENV SHELL /bin/bash
RUN if [ "$jlab" = true ]; then \
       pip3 install --no-cache-dir jupyterlab ; \
    else echo "[INFO] Skip JupyterLab installation!"; fi

# EXPERIMENTAL: install deep-start script
# N.B.: This repository also contains run_jupyter.sh
# For compatibility, create symlink /srv/.jupyter/run_jupyter.sh
RUN git clone https://github.com/deephdc/deep-start /srv/.deep-start && \
    ln -s /srv/.deep-start/deep-start.sh /usr/local/bin/deep-start && \
    ln -s /srv/.deep-start/run_jupyter.sh /usr/local/bin/run_jupyter && \
    mkdir -p /srv/.jupyter && \
    ln -s /srv/.deep-start/run_jupyter.sh /srv/.jupyter/run_jupyter.sh

# Install user app AND 
# TF Benchmarks, offical/utils/logs scripts, apply patches (if necessary)
# pull-tf_cnn_benchmarks.sh:
# identifies TF version, installs tf_cnn_benchmarks and offical/utils/logs
ENV BENCHMARK_FLAVOR ${flavor}
ENV DOCKER_BASE_IMAGE ${image}:${tag}
RUN git clone -b $branch https://github.com/deephdc/benchmarks_cnn_api && \
    cd  benchmarks_cnn_api && \
# install official TF Benchmarks
    ./pull-tf_cnn_benchmarks.sh --tfbench_path=/srv/tf_cnn_benchmarks && \
    pip3 install --no-cache-dir -e . && \
    rm -rf /root/.cache/pip/* && \
    rm -rf /tmp/* && \
    cd /srv

# Add TF Benchmarks to PYTHONPATH
ENV PYTHONPATH=/srv/tf_cnn_benchmarks

# Open DEEPaaS port
EXPOSE 5000

# Open Monitoring and Jupyter port
EXPOSE 6006 8888

# Account for OpenWisk functionality (deepaas >=0.4.0) + proper docker stop
CMD ["deepaas-run", "--openwhisk-detect", "--listen-ip", "0.0.0.0", "--listen-port", "5000"]

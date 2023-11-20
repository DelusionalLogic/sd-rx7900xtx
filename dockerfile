FROM rocm/dev-ubuntu-22.04:5.7-complete

RUN apt-get update \
	&& apt-get install -y python3-venv python3-dev git build-essential wget libgoogle-perftools4 libpng-dev libjpeg-dev

# Make a working directory
RUN mkdir /SD
WORKDIR /SD

# Create a virtual env
# @HUH: Do we actually need this? It's a container
RUN python3 -m venv /SD/venv
ENV PATH="/SD/venv/bin:$PATH"

RUN python3 -m pip install --upgrade pip wheel

# Setup the build environment for pytorch
ENV HIP_VISIBLE_DEVICES=0 \
	PYTORCH_ROCM_ARCH="gfx1100" \
	CMAKE_PREFIX_PATH=/SD/venv/ \
	USE_CUDA=0

# Setup patched folder & compile dependencies 
RUN pip install cmake ninja

# Remove old torch and torchvision
RUN pip uninstall -y torch torchvision

# Build pytorch

RUN mkdir patched \
	&& cd patched \
	&& wget https://github.com/pytorch/pytorch/releases/download/v2.1.1/pytorch-v2.1.1.tar.gz \
	&& tar -xzf pytorch-v2.1.1.tar.gz \
	&& rm -f pytorch-v2.1.1.tar.gz \
	&& cd /SD/patched/pytorch-v2.1.1 \
	&& pip install -r requirements.txt \
	&& pip install mkl mkl-include \
	&& python3 tools/amd_build/build_amd.py \
	&& python3 setup.py install \
	&& cd .. && rm -rf patched

# Build torchvision
RUN mkdir vision \
	&& cd vision \
	&& wget https://github.com/pytorch/vision/archive/refs/tags/v0.16.1.tar.gz \
	&& tar -xzf v0.16.1.tar.gz \
	&& rm -f v0.16.1.tar.gz \
	&& cd vision-0.16.1 \
	&& FORCE_CUDA=1 python3 setup.py install \
	&& cd .. && rm -rf vision

RUN git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui
WORKDIR /SD/stable-diffusion-webui
# RUN git reset --hard 22bcc7be428c94e9408f589966c2040187245d81

# Patch requirements.txt to remove torch
RUN sed '/torch/d' requirements.txt \
	&& pip install -r requirements.txt

# @HACK Fix the version ourselves
RUN echo "httpx==0.24.1" >> requirements_versions.txt

# Move the settings file so we can mount it
RUN mkdir /SD/stable-diffusion-webui/settings && \
	touch /SD/stable-diffusion-webui/settings/ui-config.json && \
	ln -s /SD/stable-diffusion-webui/settings/ui-config.json /SD/stable-diffusion-webui/ui-config.json && \
	touch /SD/stable-diffusion-webui/settings/config.json && \
	ln -s /SD/stable-diffusion-webui/settings/config.json /SD/stable-diffusion-webui/config.json

EXPOSE 7860/tcp

# Fix for "detected dubious ownership in repository" by rom1win.
RUN git config --global --add safe.directory '*'
# Workaround for some memory problems
# (see https://github.com/AUTOMATIC1111/stable-diffusion-webui/pull/9593)
ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libtcmalloc.so.4 
ENTRYPOINT [ "python3", "launch.py", "--listen", "--disable-safe-unpickle" ]

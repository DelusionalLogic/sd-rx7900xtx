#FROM rocm/composable_kernel:ck_ub20.04_rocm5.5_release
FROM rocm/dev-ubuntu-22.04:5.5.1-complete

RUN apt-get update && apt-get install -y python3-venv python3-dev git build-essential wget

# Make a working directory
RUN mkdir /SD
WORKDIR /SD

RUN python3 -m venv venv

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
RUN mkdir -p /SD/patched
RUN pip install cmake ninja

# Remove old torch and torchvision
RUN pip uninstall -y torch torchvision

# Build pytorch
RUN cd /SD/patched \
	&& wget https://github.com/pytorch/pytorch/releases/download/v2.0.1/pytorch-v2.0.1.tar.gz \
	&& tar -xzvf pytorch-v2.0.1.tar.gz \
	&& rm -f pytorch-v2.0.1.tar.gz \
	&& cd /SD/patched/pytorch-v2.0.1 \
	&& pip install -r requirements.txt \
	&& pip install mkl mkl-include \
	&& python3 tools/amd_build/build_amd.py \
	&& python3 setup.py install

# Build torchvision
RUN cd /SD/patched/ \
	&& wget https://github.com/pytorch/vision/archive/refs/tags/v0.15.2.tar.gz \
	&& tar -xzvf v0.15.2.tar.gz \
	&& cd /SD/patched/vision-0.15.2 \
	&& python3 setup.py install

RUN git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui
WORKDIR /SD/stable-diffusion-webui
# RUN git reset --hard 22bcc7be428c94e9408f589966c2040187245d81

# Patch requirements.txt to remove torch
RUN sed '/torch/d' requirements.txt
RUN pip install -r requirements.txt


# Move the settings file so we can mount it
RUN mkdir /SD/stable-diffusion-webui/settings && \
	touch /SD/stable-diffusion-webui/settings/ui-config.json && \
	ln -s /SD/stable-diffusion-webui/settings/ui-config.json /SD/stable-diffusion-webui/ui-config.json && \
	touch /SD/stable-diffusion-webui/settings/config.json && \
	ln -s /SD/stable-diffusion-webui/settings/config.json /SD/stable-diffusion-webui/config.json

EXPOSE 7860/tcp

# Fix for "detected dubious ownership in repository" by rom1win.
RUN git config --global --add safe.directory '*'
CMD python3 launch.py --listen --disable-safe-unpickle

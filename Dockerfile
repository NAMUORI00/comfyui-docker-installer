ARG COMFYUI_BASE_IMAGE=pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime
FROM ${COMFYUI_BASE_IMAGE}

ARG COMFYUI_UID=1005
ARG COMFYUI_GID=1006

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    HOME=/opt/ComfyUI/user \
    COMFYUI_DIR=/opt/ComfyUI

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      libgl1 \
      libglib2.0-0 \
      libsm6 \
      libxext6 \
      libxrender1 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}" \
    && python -m pip freeze | grep -E '^(torch|torchvision|torchaudio)==' > /tmp/torch-constraints.txt \
    && pip install --no-cache-dir -c /tmp/torch-constraints.txt -r "${COMFYUI_DIR}/requirements.txt" \
    && printf '%s\n' \
      'import torch' \
      'print("torch", torch.__version__)' \
      'print("torch_cuda", torch.version.cuda)' \
      'if not torch.version.cuda:' \
      '    raise SystemExit("CUDA build of PyTorch is required but torch.version.cuda is empty")' \
      > /tmp/check_torch_cuda.py \
    && python /tmp/check_torch_cuda.py \
    && rm /tmp/check_torch_cuda.py \
    && pip check \
    && mkdir -p "${COMFYUI_DIR}/user" \
    && chown -R "${COMFYUI_UID}:${COMFYUI_GID}" "${COMFYUI_DIR}"

WORKDIR ${COMFYUI_DIR}

EXPOSE 8188

USER ${COMFYUI_UID}:${COMFYUI_GID}

CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188"]

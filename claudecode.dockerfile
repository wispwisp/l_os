# This is file for current directory claudecode isolation.

FROM mirror.gcr.io/library/ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git npm curl wget bsdextrautils \
    && rm -rf /var/lib/apt/lists/*

ARG USER_ID
ARG GROUP_ID

# Change the existing user's ID in container
# from 1000 to something else (e.g., 2000)
# Then create your 'claudeuser' with ID match your host
RUN usermod -u 2000 ubuntu && groupmod -g 2000 ubuntu
RUN groupadd -g $GROUP_ID claudegroup && \
    useradd --uid $USER_ID --gid $GROUP_ID -m claudeuser
USER claudeuser

# Claude internal HTTP proxy on the host; only used during image build
# for this install step.  Container runtime does not require the proxy.
RUN date -u +"%Y-%m-%dT%H:%M:%SZ" > "/home/claudeuser/build-$(date -u +%Y-%m).txt"
RUN curl \
    -x http://127.0.0.1:8080 \
    -fsSL https://claude.ai/install.sh | bash
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# claude check grammar oneliner
COPY ./check_grammar.sh /usr/local/bin/check-grammar

WORKDIR /home/claudeuser/workspace
ENTRYPOINT ["bash"]

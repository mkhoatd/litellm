# Base image for building - Ubuntu with Python 3.12
FROM ubuntu:22.04 AS builder

# Set the working directory to /app
WORKDIR /app

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install Python 3.12, Node.js, npm, and build dependencies
RUN apt-get update && apt-get install -y \
    software-properties-common \
    curl \
    gcc \
    g++ \
    python3-dev \
    openssl \
    libssl-dev \
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y \
    python3.12 \
    python3.12-dev \
    python3.12-venv \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create symbolic links for Python 3.12 as default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# Install pip for Python 3.12
RUN curl https://bootstrap.pypa.io/get-pip.py | python3.12

RUN pip install --upgrade pip && \
    pip install build

# Copy the current directory contents into the container at /app
COPY . .

# Build Admin UI
RUN chmod +x docker/build_admin_ui.sh && ./docker/build_admin_ui.sh

# Build the package
RUN rm -rf dist/* && python -m build

# There should be only one wheel file now, assume the build only creates one
RUN ls -1 dist/*.whl | head -1

# Install the package
RUN pip install dist/*.whl

# install dependencies as wheels
RUN pip wheel --no-cache-dir --wheel-dir=/wheels/ -r requirements.txt

# ensure pyjwt is used, not jwt
RUN pip uninstall jwt -y
RUN pip uninstall PyJWT -y
RUN pip install PyJWT==2.9.0 --no-cache-dir

# Build Admin UI
RUN chmod +x docker/build_admin_ui.sh && ./docker/build_admin_ui.sh

# Runtime stage - Ubuntu with Python 3.12
FROM ubuntu:22.04 AS runtime

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install Python 3.12, Node.js and runtime dependencies
RUN apt-get update && apt-get install -y \
    software-properties-common \
    curl \
    openssl \
    tzdata \
    supervisor \
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y \
    python3.12 \
    python3.12-venv \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create symbolic links for Python 3.12 as default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# Install pip for Python 3.12
RUN curl https://bootstrap.pypa.io/get-pip.py | python3.12

WORKDIR /app
# Copy the current directory contents into the container at /app
COPY . .
RUN ls -la /app

# Copy the built wheel from the builder stage to the runtime stage; assumes only one wheel file is present
COPY --from=builder /app/dist/*.whl .
COPY --from=builder /wheels/ /wheels/

# Install the built wheel using pip; again using a wildcard if it's the only file
RUN pip install *.whl /wheels/* --no-index --find-links=/wheels/ && rm -f *.whl && rm -rf /wheels

# Install semantic_router without dependencies
RUN pip install semantic_router --no-deps

# Generate prisma client
RUN prisma generate
RUN chmod +x docker/entrypoint.sh
RUN chmod +x docker/prod_entrypoint.sh

EXPOSE 4000/tcp

# Copy supervisor configuration
COPY docker/supervisord.conf /etc/supervisord.conf

ENTRYPOINT ["docker/prod_entrypoint.sh"]

# Append "--detailed_debug" to the end of CMD to view detailed debug logs
CMD ["--port", "4000"]

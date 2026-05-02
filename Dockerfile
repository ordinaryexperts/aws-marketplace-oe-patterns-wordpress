FROM ordinaryexperts/aws-marketplace-patterns-devenv:2.8.4
# FROM devenv:latest
# 2.8.4 bakes in playwright + chromium so `make test-integration` works
# without per-run pip installs / browser downloads.

# install dependencies
RUN mkdir -p /tmp/code/cdk/wordpress
COPY ./cdk/requirements.txt /tmp/code/cdk/
COPY ./cdk/setup.py /tmp/code/cdk/
RUN touch /tmp/code/cdk/README.md
WORKDIR /tmp/code/cdk
RUN pip3 install -r requirements.txt --break-system-packages
RUN rm -rf /tmp/code

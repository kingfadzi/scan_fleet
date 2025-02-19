# Use a base image with DNF (e.g., Fedora or CentOS)
FROM fedora:latest

# Set environment variables for Gradle versions and base URL
ENV GRADLE_VERSIONS="7.4 7.5" \
    GRADLE_DISTRIBUTIONS_BASE_URL="https://services.gradle.org/distributions/"

# Install dependencies, download and install Gradle versions
RUN set -e && \
    dnf install -y unzip wget && \
    mkdir -p /opt/gradle && \
    for VERSION in $GRADLE_VERSIONS; do \
        FULL_URL="${GRADLE_DISTRIBUTIONS_BASE_URL}gradle-${VERSION}-bin.zip"; \
        echo "Installing Gradle $VERSION from $FULL_URL..."; \
        wget "$FULL_URL" -O /tmp/gradle-${VERSION}-bin.zip || { echo "Error: Failed to download Gradle $VERSION" >&2; exit 1; }; \
        unzip -qo /tmp/gradle-${VERSION}-bin.zip -d /opt/gradle || { echo "Error: Failed to unzip Gradle $VERSION" >&2; exit 1; }; \
        rm /tmp/gradle-${VERSION}-bin.zip; \
        ln -s "/opt/gradle/gradle-${VERSION}/bin/gradle" "/usr/local/bin/gradle-${VERSION}"; \
    done && \
    dnf clean all

# Set the default Gradle version (optional)
ENV PATH="/opt/gradle/gradle-7.5/bin:${PATH}"

# Verify Gradle installation
RUN gradle-7.5 --version

# Default command (optional)
CMD ["bash"]

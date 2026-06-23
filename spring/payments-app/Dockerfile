# =============================================================================
# spring/payments-app/Dockerfile
#
# Multi-stage build:
#   Stage 1 (builder) — compiles the Maven project using Java 23
#   Stage 2 (runtime) — runs the JAR as a non-root user on Java 23 JRE
#
# The secrets file is NOT baked into the image. It is provided at runtime
# by Vault Agent via the bind-mounted secrets/ directory.
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: build
# Use the official Maven image with Java 23 so mvn is available on PATH.
# ---------------------------------------------------------------------------
FROM maven:3.9-eclipse-temurin-23 AS builder

WORKDIR /build

# Copy dependency descriptors first to exploit Docker layer caching —
# dependencies are only re-downloaded when pom.xml changes.
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 \
    mvn dependency:go-offline -B 2>/dev/null || true

# Copy source and build the fat JAR, skipping tests (tests require a live
# database and secrets file which are not available at image build time).
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 \
    mvn package -DskipTests -B

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM eclipse-temurin:23-jre AS runtime

# Create a non-root user to run the application.
RUN useradd -m -u 1001 appuser

WORKDIR /app

# Copy only the fat JAR from the builder stage.
COPY --from=builder /build/target/*.jar app.jar

# The secrets volume is mounted here at runtime by docker-compose.yml.
# Spring Boot imports /vault/secrets/application.properties via
# SPRING_CONFIG_IMPORT. If the file is absent on startup the app fast-fails.
RUN mkdir -p /vault/secrets && chown appuser:appuser /vault/secrets

USER 1001

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]

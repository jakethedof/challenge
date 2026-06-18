# ─────────────────────────────────────────────────────────
# Stage 1: Build
# Uses the full JDK + Maven wrapper to compile the app.
# ─────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jdk-alpine AS builder

WORKDIR /app

# Copy dependency manifests first to exploit Docker layer cache:
# if pom.xml hasn't changed, the dependency download layer is reused.
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN ./mvnw dependency:go-offline -B

COPY src/ src/
RUN ./mvnw package -DskipTests -B

# Spring Boot layertools splits the fat-jar into dependency layers,
# so only the changed layer (usually 'application') is re-pushed to ACR.
RUN java -Djarmode=layertools -jar target/*.jar extract --destination target/extracted

# ─────────────────────────────────────────────────────────
# Stage 2: Runtime
# Minimal JRE image — no compiler, no shell, no build tools.
# ─────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine AS runtime

# Non-root user (security best practice)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy layered extraction output from builder (preserves caching order)
COPY --from=builder --chown=appuser:appgroup /app/target/extracted/dependencies/          ./
COPY --from=builder --chown=appuser:appgroup /app/target/extracted/spring-boot-loader/    ./
COPY --from=builder --chown=appuser:appgroup /app/target/extracted/snapshot-dependencies/ ./
COPY --from=builder --chown=appuser:appgroup /app/target/extracted/application/           ./

USER appuser

EXPOSE 8080

# Spring Boot Actuator health endpoint used for liveness/readiness probes
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD wget -qO- http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]

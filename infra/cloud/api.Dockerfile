FROM maven:3.9.11-eclipse-temurin-21 AS build
WORKDIR /build
COPY jchatmind/pom.xml ./pom.xml
RUN --mount=type=cache,target=/root/.m2 mvn -B -q dependency:go-offline
COPY jchatmind/src ./src
# Local development configuration must never enter the deployable JAR. The
# external cloud profile below supplies the full runtime configuration instead.
RUN --mount=type=cache,target=/root/.m2 rm -f src/main/resources/application*.yaml src/main/resources/application*.yml \
    && mvn -B -q -DskipTests package

FROM eclipse-temurin:21-jre-jammy
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 jchatmind \
    && useradd --uid 10001 --gid 10001 --create-home jchatmind \
    && mkdir -p /app/data/documents && chown -R jchatmind:jchatmind /app
WORKDIR /app
COPY --from=build --chown=10001:10001 /build/target/jchatmind-0.0.1-SNAPSHOT.jar /app/app.jar
COPY --chown=10001:10001 infra/cloud/application-cloud.yaml /app/config/application-cloud.yaml
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar", "--spring.profiles.active=cloud"]

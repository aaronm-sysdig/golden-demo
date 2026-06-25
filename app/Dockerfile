# Stage 1: build the WAR. Internet needed here (build time only).
FROM maven:3.6.3-amazoncorretto-8 AS build
WORKDIR /src
COPY pom.xml .
COPY src ./src
RUN mvn -q -DskipTests package

# Stage 2: runtime. Old Tomcat + JDK8 = reliable S2-045 + rich base-image CVEs.
FROM tomcat:8.5.99-jre8-temurin
# psql client baked in at build time (no runtime downloads - air-gap safe).
RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client \
    && rm -rf /var/lib/apt/lists/*
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=build /src/target/customer-portal.war /usr/local/tomcat/webapps/ROOT.war
RUN mkdir -p /root/.aws && printf '[default]\naws_access_key_id = AKIAIOSFODNN7EXAMPLE\naws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY\nregion = ap-southeast-2\n' > /root/.aws/credentials
EXPOSE 8080

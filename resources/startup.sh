#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

JENKINS_HOME_DIR="/var/lib/jenkins"

run_main() {
  INIT_SCRIPT_FOLDER="${JENKINS_HOME_DIR}/init.groovy.d"
  # TODO rename resources to jenkins
  MAIN_INIT_SCRIPTS_FOLDER="/var/tmp/resources/init.groovy.d"
  CUSTOM_INIT_SCRIPTS_FOLDER="/var/lib/custom.init.groovy.d"

  # set state to installing
  doguctl state 'installing'

  # create truststore for java processes
  TRUSTSTORE="${JENKINS_HOME_DIR}/truststore.jks"
  create_truststore.sh "${TRUSTSTORE}" > /dev/null

  # create ca store for git, mercurial and subversion
  create-ca-certificates.sh "${JENKINS_HOME_DIR}/ca-certificates.crt"
  createCurlCertificates "${JENKINS_HOME_DIR}"

  # copy init scripts

  # remove old folder to be sure,
  # that it contains no script which is already removed from custom init script folder
  if [ -d "${INIT_SCRIPT_FOLDER}" ]; then
    rm -rf "${INIT_SCRIPT_FOLDER}"
  fi

  # copy fresh main init scripts
  cp -rf "${MAIN_INIT_SCRIPTS_FOLDER}" "${INIT_SCRIPT_FOLDER}"

  # merge custom init scripts, if the volume is not empty
  if [ "$(ls -A ${CUSTOM_INIT_SCRIPTS_FOLDER})" ]; then
    cp "${CUSTOM_INIT_SCRIPTS_FOLDER}"/* "${INIT_SCRIPT_FOLDER}"/scripts
  fi

  # set initial setting for slave-to-master-security
  # see https://wiki.jenkins-ci.org/display/JENKINS/Slave+To+Master+Access+Control
  SLAVE_TO_MASTER_SECURITY="${JENKINS_HOME_DIR}/secrets/slave-to-master-security-kill-switch"
  if [ ! -f "${SLAVE_TO_MASTER_SECURITY}" ]; then
    SECRETS_DIRECTORY=$(dirname "${SLAVE_TO_MASTER_SECURITY}")
    if [ ! -d "${SECRETS_DIRECTORY}" ]; then
      mkdir -p "${SECRETS_DIRECTORY}"
    fi
    echo 'false' > "${SLAVE_TO_MASTER_SECURITY}"
  fi

  # Disable CLI over Remoting as advised with Jenkins LTS 2.46.2
  # see https://jenkins.io/blog/2017/04/26/security-advisory/
  CLI_CONFIG_FILE="${JENKINS_HOME_DIR}/jenkins.CLI.xml"
  if [ ! -f "${CLI_CONFIG_FILE}" ]; then
    cp /var/tmp/resources/jenkins.CLI.xml "${CLI_CONFIG_FILE}"
    chmod 0644 "${CLI_CONFIG_FILE}"
  fi

  # Set maven truststore options in .mavenrc file so they won't get copied to slave machines
  if [[ ! -e /var/lib/jenkins/.mavenrc ]]; then
    echo "MAVEN_OPTS=\"\$MAVEN_OPTS -Djavax.net.ssl.trustStore=${TRUSTSTORE}\"" > "${JENKINS_HOME_DIR}/.mavenrc"
    echo "MAVEN_OPTS=\"\$MAVEN_OPTS -Djavax.net.ssl.trustStorePassword=changeit\"" >> "${JENKINS_HOME_DIR}/.mavenrc"
  fi

  # starting jenkins
  if [[ "$(doguctl config "container_config/memory_limit" -d "empty")" == "empty" ]];  then
    echo "Starting Jenkins without memory limits..."
    java -Djava.awt.headless=true \
      -Djava.net.preferIPv4Stack=true \
      -Djavax.net.ssl.trustStore="${TRUSTSTORE}" \
      -Djavax.net.ssl.trustStorePassword=changeit \
      -Djenkins.install.runSetupWizard=false \
      -Djava.awt.headless=true \
      -jar /jenkins.war --prefix=/jenkins
  else
    # Retrieve configurable java limits from etcd, valid default values exist
    MEMORY_LIMIT_MAX_PERCENTAGE=$(doguctl config "container_config/java_max_ram_percentage")
    MEMORY_LIMIT_MIN_PERCENTAGE=$(doguctl config "container_config/java_min_ram_percentage")
    echo "Starting Jenkins with memory limits: MaxRAMPercentage=${MEMORY_LIMIT_MAX_PERCENTAGE}, MinRAMPercentage=${MEMORY_LIMIT_MIN_PERCENTAGE} ..."
    java -Djava.awt.headless=true \
      -Djava.net.preferIPv4Stack=true \
      -Djavax.net.ssl.trustStore="${TRUSTSTORE}" \
      -Djavax.net.ssl.trustStorePassword=changeit \
      -Djenkins.install.runSetupWizard=false \
      -Djava.awt.headless=true \
      -XX:MaxRAMPercentage="${MEMORY_LIMIT_MAX_PERCENTAGE}" \
      -XX:MinRAMPercentage="${MEMORY_LIMIT_MIN_PERCENTAGE}" \
      -jar /jenkins.war --prefix=/jenkins
  fi
}

function createCurlCertificates() {
  homeDir="${1}"
  echo "cacert = ${homeDir}/ca-certificates.crt" > "${homeDir}/.curlrc"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_main
fi

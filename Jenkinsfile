#!groovy
@Library(['github.com/cloudogu/ces-build-lib@1.43.0', 'github.com/cloudogu/dogu-build-lib@a14afd9d', 'github.com/cloudogu/zalenium-build-lib@30923630ced3089ae0861bef25b60903429841aa'])
import com.cloudogu.ces.cesbuildlib.*
import com.cloudogu.ces.dogubuildlib.*
import com.cloudogu.ces.zaleniumbuildlib.*

node('docker'){
        stage('Checkout') {
            checkout scm
        }

        stage('Lint') {
            lintDockerfile()
            shellCheck("resources/startup.sh resources/upgrade-notification.sh")
        }
}

node('vagrant') {

    String doguName = "jenkins"
    Git git = new Git(this, "cesmarvin")
    git.committerName = 'cesmarvin'
    git.committerEmail = 'cesmarvin@cloudogu.com'
    GitFlow gitflow = new GitFlow(this, git)
    GitHub github = new GitHub(this, git)
    Changelog changelog = new Changelog(this)

    timestamps{
        properties([
            // Keep only the last x builds to preserve space
            buildDiscarder(logRotator(numToKeepStr: '10')),
            // Don't run concurrent builds for a branch, because they use the same workspace directory
            disableConcurrentBuilds(),
            // Parameter to activate dogu upgrade test on demand
            parameters([
                booleanParam(defaultValue: false, description: 'Test dogu upgrade from latest release', name: 'TestDoguUpgradeFromLatestRelease')
            ])
        ])

        EcoSystem ecoSystem = new EcoSystem(this, "gcloud-ces-operations-internal-packer", "jenkins-gcloud-ces-operations-internal")

        try {

            stage('Provision') {
                ecoSystem.provision("/dogu");
            }

            stage('Setup') {
                ecoSystem.loginBackend('cesmarvin-setup')
                ecoSystem.setup()
            }

            stage('Wait for dependencies') {
                timeout(15) {
                    ecoSystem.waitForDogu("cas")
                    ecoSystem.waitForDogu("usermgt")
                }
            }

            stage('Build') {
                ecoSystem.build("/dogu")
            }

            stage('Verify') {
                ecoSystem.verify("/dogu")
            }

            stage('Integration Tests') {

                String externalIP = ecoSystem.externalIP

                if (fileExists('integrationTests/it-results.xml')) {
                    sh 'rm -f integrationTests/it-results.xml'
                }

                timeout(time: 15, unit: 'MINUTES') {

                    try {

                        withZalenium { zaleniumIp ->

                            dir('integrationTests') {

                                docker.image('node:8.14.0-stretch').inside("-e WEBDRIVER=remote -e CES_FQDN=${externalIP} -e SELENIUM_BROWSER=chrome -e SELENIUM_REMOTE_URL=http://${zaleniumIp}:4444/wd/hub") {
                                    sh 'yarn install'
                                    sh 'yarn run ci-test'
                                }

                            }

                        }
                    } finally {
                        // archive test results
                        junit allowEmptyResults: true, testResults: 'integrationTests/it-results.xml'
                    }
                }
            }

            if (params.TestDoguUpgradeFromLatestRelease != null && params.TestDoguUpgradeFromLatestRelease){
                stage('Upgrade test') {
                    // Remove new dogu that has been built and tested above
                    ecoSystem.purge(doguName)

                    // Install latest released version of dogu
                    ecoSystem.install("official/" + doguName)

                    // Start dogu and wait until it is up
                    ecoSystem.start(doguName)
                    ecoSystem.waitForDogu(doguName)

                    // Upgrade dogu by building again
                    // currentDoguVersionString, e.g. "Version": "2.222.4-1",
                    String currentDoguVersionString = sh(returnStdout: true, script: 'grep .Version dogu.json').trim()
                    // releaseNumber, e.g. 1
                    int releaseNumber = (currentDoguVersionString.split('-')[1] - "\",").toInteger()
                    // newReleaseNumber, e.g. 2
                    int newReleaseNumber = releaseNumber + 1
                    print "new number: ${newReleaseNumber}"
                    // currentDoguVersion, e.g. 2.222.4-1
                    String currentDoguVersion = currentDoguVersionString.split("\"")[3]
                    print "current dogu version: ${currentDoguVersion}"
                    // newDoguVersion, e.g. 2.222.4-2
                    String newDoguVersion = currentDoguVersion.split("-")[0] + "-" + newReleaseNumber
                    print "newDoguVersion = ${newDoguVersion}"
                    ecoSystem.setVersion(newDoguVersion)
                    ecoSystem.vagrant.sync()
                    ecoSystem.build("/dogu")
                    ecoSystem.waitForDogu(doguName)

                    // Run integration tests again to verify that the upgrade was successful
                    // see above
                }

            }

            if (gitflow.isReleaseBranch()) {
                String releaseVersion = git.getSimpleBranchName();

                stage('Finish Release') {
                    gitflow.finishRelease(releaseVersion)
                }

                stage('Push Dogu to registry') {
                    ecoSystem.push("/dogu")
                }

                stage ('Add Github-Release'){
                    github.createReleaseWithChangelog(releaseVersion, changelog)
                }
            }

        } finally {
            stage('Clean') {
                ecoSystem.destroy()
            }
        }
    }
}

node 
{
  stage('========== Clone repository ==========') {
    checkout scm
    }
 stage('Ready'){
        sh "echo 'Ready to build'"
        mvnHome = tool 'mvnHome'
        }

    // mvn 빌드로 jar파일을 생성하는 stage
    stage('Build'){
        sh "echo 'Build Spring Boot Jar'"
        sh "pwd"
        sh "cd demo && /var/lib/jenkins/tools/hudson.tasks.Maven_MavenInstallation/mvnHome/bin/mvn clean package"
    }
  stage('========== Build image ==========') {
    app = docker.build("koomzc/${env.IMAGE_NAME}")
  }
  stage('========== Push image ==========') {
    docker.withRegistry('https://harbor.taskoo.net', 'Harbor') {
      app.push("${env.BUILD_NUMBER}")
      app.push("latest")
    }
  }
}
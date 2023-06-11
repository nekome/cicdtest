# 要件
- NginxコンテナーをAWS上で起動し、インターネットからそのNginxにアクセスして "Welcome to
ntinx" が確認可能なIaC(Infrastructure as a code)を作成してください
- そのIaCをgithubで公開してください
- 可能であればAWSのコンテナーオーケストレーションツールEKSやECSを使ってください
- READEME.mdにその内容を再現するためのドキュメントを作成してください

# 実行方法
## 前提条件
- terraformが導入されており、teraformコマンドが実行可能であること
- terraform versionはv1.3.7であること
- aws cliが導入されていること
- awsのアカウントが作成されていること
- 

terraform init

terraform plan

terraform apply

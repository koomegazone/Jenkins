# Lab3 : Terraform Modularization
더 고도화 된 Terraform 구조 설계를 위해 Working Directory 분리 및 Module화를 수행해보고, 이에 따른 의존성 관리 기법을 학습합니다.

## Challenge 1: terraform modularization

더 고도화 된 Terraform 구조 설계를 위해 워킹 디렉토리 분리 및 Module화를 수행해보고, 이에 따른 의존성 관리 기법을 학습합니다.



### Introduction

본 실습에서는 Terraform의 고급 아키텍처 설계 기법을 단계별로 학습합니다. 실무에서 자주 마주하는 상황을 시뮬레이션하여 단일 워킹 디렉토리에서 시작해 점진적으로 발전시켜 나가는 과정을 통해 재사용 가능하고 확장 가능한 Terraform 구조를 구축합니다.

현재 여러분의 조직에서는 VPC, Security Group, EC2 인스턴스가 모두 하나의 Terraform 프로젝트에서 관리되고 있습니다. 하지만 조직이 성장하면서 네트워크 팀, 보안 팀, 애플리케이션 팀이 각각 다른 리소스를 담당하게 되었고, 동일한 state 파일을 공유해야 하는 상황이 발생했습니다. 한 팀의 변경사항이 다른 팀의 작업에 영향을 미치고, 기존 인프라와 새로운 인프라를 함께 관리해야 하는 복잡성이 증가하면서 코드 재사용성 부족으로 인한 중복 코드도 늘어나고 있습니다.

이러한 문제를 해결하기 위해 본 실습에서는 실제 AWS 환경에서 VPC, Security Group, EC2 인스턴스를 생성하고 관리하면서 Terraform 구조를 점진적으로 개선해 나갑니다. 실습용으로 축소된 환경이지만, 실제 대규모 인프라에서 적용할 수 있는 핵심 패턴들을 모두 다룹니다.

기존 단일 워킹 디렉토리 구조를 배포하고 분석한 후, VPC, Security Group, EC2를 독립적인 워킹 디렉토리로 분리하여 팀별 독립 작업 환경을 구성합니다. 이후 terraform_remote_state에서 데이터소스 기반 참조로 전환하고 하이브리드 참조 패턴을 구현하여 의존성 관리를 개선합니다. 다음 단계에서는 기존 워킹 디렉토리를 재사용 가능한 모듈 구조로 전환하고, 마지막으로 Function Module을 통한 공통 로직 추상화 및 복합 워킹 디렉토리를 구성하여 고급 패턴을 적용합니다.

실습을 완료하면 프로덕션 환경에서 확장 가능하고 유지보수가 용이한 Terraform 아키텍처를 설계하고 구현할 수 있는 실무 역량을 갖추게 됩니다. 특히 팀 간 협업이 필요한 복잡한 인프라 환경에서 효율적인 Terraform 관리 전략을 수립할 수 있습니다.

### Step 1: 단일 구조 이해와 초기 배포

이 단계에서는 현재 단일 워킹 디렉토리 구조를 직접 배포합니다. VPC와 EC2 인스턴스를 프로비저닝하는 코드는 이미 생성되었으며, `/root/code/terraform` 디렉터리에서 확인할 수 있습니다. `Code` 탭을 클릭하여 파일 구조를 검토할 수 있습니다.

파일 구조는 다음과 유사해야 합니다:

```bash
terraform
└── project
    ├── main-ec2.tf
    ├── main-sg.tf
    ├── main-vpc.tf
    ├── outputs-ec2.tf
    ├── outputs-sg.tf
    ├── outputs-vpc.tf
    ├── variables-ec2.auto.tfvars
    ├── variables-ec2.tf
    ├── variables-sg.auto.tfvars
    ├── variables-sg.tf
    ├── variables-vpc.auto.tfvars
    └── variables-vpc.tf
```
현재 파일 구조에서는 VPC 관련 리소스(VPC, Subnet, Gateway, Route Table)과 EC2 관련 리소스(Security Group, EC2 Instance)가 모두 하나의 state 파일에서 관리됩니다. 현재 구조로 인프라를 배포해보겠습니다.

`Shell` 탭에서 `init`과 `plan`을 수행합니다:

```bash
cd /root/code/terraform/project
terraform init
terraform plan
```
`plan` 결과를 검토해 의도한 변경만 포함되는지 확인합니다. 총 19개의 리소스가 생성될 예정입니다.

다음으로 변경 사항을 적용합니다. `apply`를 실행해 인프라를 생성합니다:

```bash
terraform apply --auto-approve
```
인프라 생성에는 약 5분 이상 소요됩니다. NAT Gateway와 같은 네트워크 리소스 생성에 시간이 걸리기 때문입니다. 아래 출력 결과를 확인하면 다음 Step으로 넘어갈 준비가 된 것입니다:

```bash
Apply complete! Resources: 19 added, 0 changed, 0 destroyed.
```
이를 통해 단일 워킹 디렉토리 구조에서 VPC, Security Group, EC2 인스턴스가 모두 하나의 state 파일에서 관리되는 기본 구조를 성공적으로 배포했습니다. 이 구조는 간단하지만 팀 간 협업이 필요한 복잡한 환경에서는 여러 한계점을 가지고 있습니다. 다음 단계에서는 이러한 한계점을 해결하기 위해 워킹 디렉토리를 분리하고 state 파일을 복원하는 작업을 진행하겠습니다.

### Step 2: 독립 워킹 디렉토리 전환

#### 2.1. 기존 리소스를 import 준비
워킹 디렉토리를 분리하기 전에, 이미 생성된 리소스를 새로운 구조의 terraform state 파일에 보존하기 위해 모든 리소스에 대한 import를 수행해야 합니다. VPC, Security Group, EC2 관련 리소스끼리 각각 import를 수행하는 파일을 생성하겠습니다.

먼저, import 파일의 토대가 될 템플릿 파일을 생성합니다. 이 템플릿은 리소스 정보를 받아 import 구문을 생성하는 역할을 합니다.

`Shell`에서 다음 명령을 실행합니다:

```bash
cd /root/code/terraform/project
mkdir imports
cat > imports/import.tftpl << 'EOF'
%{ for resource in resources ~}
import {
  to = ${resource.to}
  id = "${resource.id}"
}

%{ endfor ~}
EOF
```
다음으로 템플릿 파일을 이용하여 실제 import 파일을 생성할 generate-import 파일들을 생성합니다. 각 리소스 유형별로 별도의 파일을 만들어 관리합니다.

다음 커맨드를 실행하세요:

```bash
cat > generate-imports-vpc.tf << 'EOF'
locals {
  vpc_import_list = [{
    to = "aws_vpc.this"
    id = aws_vpc.this.id
  }]

  subnet_import_list = [for key, subnet in aws_subnet.these : {
    to = "aws_subnet.these[\"${key}\"]"
    id = subnet.id
  }]

  internet_gateway_import_list = [{
    to = "aws_internet_gateway.this"
    id = aws_internet_gateway.this.id
  }]

  eip_import_list = [for key, eip in aws_eip.these : {
    to = "aws_eip.these[\"${key}\"]"
    id = eip.id
  }]

  nat_gateway_import_list = [for key, nat_gateway in aws_nat_gateway.these : {
    to = "aws_nat_gateway.these[\"${key}\"]"
    id = nat_gateway.id
  }]

  route_table_import_list = [for key, route_table in aws_route_table.these : {
    to = "aws_route_table.these[\"${key}\"]"
    id = route_table.id
  }]

  route_table_association_import_list = [for key, route_table_association in aws_route_table_association.these : {
    to = "aws_route_table_association.these[\"${key}\"]"
    id = "${route_table_association.subnet_id}/${route_table_association.route_table_id}"
  }]

  route_import_list = [for key, route in aws_route.these : {
    to = "aws_route.these[\"${key}\"]"
    id = "${route.route_table_id}_${route.destination_cidr_block}"
  }]
}

resource "local_file" "import_vpc" {
  filename = "${path.module}/imports/import-vpc.tf"
  content = templatefile("${path.module}/imports/import.tftpl", {
    resources = concat(
      local.vpc_import_list,
      local.subnet_import_list,
      local.internet_gateway_import_list,
      local.eip_import_list,
      local.nat_gateway_import_list,
      local.route_table_import_list,
      local.route_table_association_import_list,
      local.route_import_list
    )
  })
}
EOF

cat > generate-imports-sg.tf << 'EOF'
locals {
  security_group_import_list = [for key, security_group in aws_security_group.these : {
    to = "aws_security_group.these[\"${key}\"]"
    id = security_group.id
  }]

  security_group_rule_import_list = [for key, security_group_rule in aws_security_group_rule.these : {
    to = "aws_security_group_rule.these[\"${key}\"]"
    id = (security_group_rule.cidr_blocks != null
      ? "${security_group_rule.security_group_id}_${security_group_rule.type}_${security_group_rule.protocol}_${security_group_rule.from_port}_${security_group_rule.from_port}_${security_group_rule.cidr_blocks[0]}"
      : "${security_group_rule.security_group_id}_${security_group_rule.type}_${security_group_rule.protocol}_${security_group_rule.from_port}_${security_group_rule.from_port}_${security_group_rule.source_security_group_id}"
    )
  }]

}

resource "local_file" "import_security_group" {
  filename = "${path.module}/imports/import-sg.tf"
  content = templatefile("${path.module}/imports/import.tftpl", {
    resources = concat(
      local.security_group_import_list,
      local.security_group_rule_import_list,
    )
  })
}
EOF

cat > generate-imports-ec2.tf << 'EOF'
locals {
  ec2_instance_import_list = [{
    to = "aws_instance.this"
    id = aws_instance.this.id
  }]
}

resource "local_file" "import_ec2_instance" {
  filename = "${path.module}/imports/import-ec2.tf"
  content = templatefile("${path.module}/imports/import.tftpl", {
    resources = concat(
      local.ec2_instance_import_list
    )
  })
}
EOF
```
파일 구조에 아래와 같은 파일들이 생성되었습니다. 각각의 generate-import 파일은 다음번 `apply` 수행 시 "import.tftpl" 파일을 이용하여 VPC, Security Group, EC2 리소스끼리 각각의 "import.tf" 파일을 생성할 것입니다.

다음 파일 구조는 다음과 유사해야 합니다:

```bash
terraform
└── project
    ├── imports
    │   └── import.tftpl
    ├── generate-imports-ec2.tf
    ├── generate-imports-sg.tf
    ├── generate-imports-vpc.tf
```
generate-import 파일들을 실행하여 실제 import 파일들을 생성합니다.

아래 커맨드를 실행하세요:

```bash
terraform init
terraform apply -auto-approve
```
실행이 완료되면 다음과 같이 import 파일들이 생성됩니다. 이 파일들은 각각의 워킹 디렉토리에서 기존 리소스를 import할 때 사용됩니다:

```bash
terraform
└── project
    ├── imports
    │   ├── import-ec2.tf  <- 새롭게 생성된 import 파일
    │   ├── import-sg.tf   <- 새롭게 생성된 import 파일
    │   ├── import-vpc.tf  <- 새롭게 생성된 import 파일
    │   └── import.tftpl
    ├── generate-imports-ec2.tf
    ├── generate-imports-sg.tf
    ├── generate-imports-vpc.tf
```
이를 통해 각 리소스 유형별로 import 파일을 생성할 수 있는 템플릿과 생성 로직이 준비되었습니다. 이 구조를 통해 VPC, Security Group, EC2 리소스를 각각 독립적인 워킹 디렉토리로 안전하게 이동할 수 있는 기반이 마련되었습니다. 다음 단계에서는 실제 워킹 디렉토리 분리 작업을 진행하겠습니다.

#### 2.2. 워킹 디렉토리 분리
이 단계에서는 단일 워킹 디렉토리에서 관리되던 모든 리소스를 VPC, Security Group, EC2 세 개의 독립적인 워킹 디렉토리로 분리합니다. 이를 통해 각 팀이 담당 리소스만 독립적으로 관리할 수 있는 환경을 구성하고, 한 팀의 변경사항이 다른 팀에 미치는 영향을 최소화할 수 있습니다.

기존 프로젝트를 백업하고 새로운 디렉토리 구조를 생성합니다. `Shell`에서 다음 명령을 실행합니다:

```bash
cd /root/code/terraform
mv project project-old
mkdir project
mkdir project/vpc
mkdir project/ec2
mkdir project/sg
cp project-old/variables-vpc.tf project/vpc/variables.tf
cp project-old/variables-sg.tf project/sg/variables.tf
cp project-old/variables-ec2.tf project/ec2/variables.tf
cp project-old/variables-vpc.auto.tfvars project/vpc/variables.auto.tfvars
cp project-old/variables-sg.auto.tfvars project/sg/variables.auto.tfvars
cp project-old/variables-ec2.auto.tfvars project/ec2/variables.auto.tfvars
cp project-old/main-vpc.tf project/vpc/main.tf
cp project-old/main-sg.tf project/sg/main.tf
cp project-old/main-ec2.tf project/ec2/main.tf
cp project-old/outputs-vpc.tf project/vpc/outputs.tf
cp project-old/outputs-sg.tf project/sg/outputs.tf
cp project-old/outputs-ec2.tf project/ec2/outputs.tf
cp project-old/imports/import-vpc.tf project/vpc/import.tf
cp project-old/imports/import-sg.tf project/sg/import.tf
cp project-old/imports/import-ec2.tf project/ec2/import.tf
```
새로운 디렉토리 구조는 다음과 같아야 합니다. `Code` 탭에서 파일 구조를 확인하세요:

```bash
terraform
├── project-old   <- 기존의 소스코드와 terraform state 파일이 있는 프로젝트 디렉토리
└── project       <- 새로운 프로젝트 디렉토리
    ├── ec2
    │   ├── import.tf
    │   ├── main.tf
    │   ├── outputs.tf
    │   ├── variables.auto.tfvars
    │   └── variables.tf
    ├── sg
    │   ├── import.tf
    │   ├── main.tf
    │   ├── outputs.tf
    │   ├── variables.auto.tfvars
    │   └── variables.tf
    └── vpc
        ├── import.tf
        ├── main.tf
        ├── outputs.tf
        ├── variables.auto.tfvars
        └── variables.tf
```
이를 통해 기존 단일 워킹 디렉토리 구조를 세 개의 독립적인 워킹 디렉토리로 성공적으로 분리했습니다. 각 디렉토리는 해당 리소스 유형에 필요한 모든 파일과 import 정보를 포함하고 있습니다. 다음 단계에서는 각 워킹 디렉토리에서 기존 리소스를 import하여 state 파일을 복원하고, 디렉토리 간 의존성을 설정하겠습니다.

#### 2.3 State 복원
이 단계에서는 분리된 각 워킹 디렉토리에서 기존 리소스를 import하여 Terraform state 파일을 복원합니다. 또한 디렉토리 간 의존성을 설정하여 각 리소스가 다른 리소스를 정상적으로 참조할 수 있도록 구성합니다. VPC는 다른 리소스들의 기반이 되므로 가장 처리하고, Security Group과 EC2 순서로 진행합니다.

1. VPC 워킹 디렉토리 복원

    제일 먼저, VPC 워킹 디렉토리에서 리소스를 import하여 terraform state를 복원하겠습니다. VPC는 다른 리소스들의 기반이 되므로 가장 처리합니다.

    `Shell` 탭에서 `init`과 `plan`을 수행합니다:

    ```bash
    cd /root/code/terraform/project/vpc
    terraform init
    terraform plan
    ```
    `plan` 결과를 검토해 의도한 변경만 포함되는지 확인합니다. 16개의 리소스가 import될 예정이며, 새 리소스가 생성되지 않아야 합니다.

    다음으로 변경 사항을 적용합니다. `apply`를 실행해 import를 실행합니다:

    ```bash
    terraform apply --auto-approve
    ```
    VPC 리소스를 성공적으로 import하면 다음과 같은 출력 결과를 확인할 수 있습니다:

    ```bash
    Apply complete! Resources: 16 imported, 0 added, 0 changed, 0 destroyed.
    ```

2. Security Group 워킹 디렉토리 복원

    Security Group은 VPC에 의존하므로 VPC 정보를 참조할 수 있도록 설정해야 합니다.

    SG 워킹 디렉토리의 main.tf를 보면, vpc_id를 입력받아야 하는 부분이 있는데, VPC 워킹 디렉토리와 분리되었기 때문에 별도로 의존성을 설정해주지 않으면 에러가 발생합니다.

    참고용 파일/디렉토리 구조:

    ```bash
    resource "aws_security_group" "these" {
    for_each = local.security_group_map

    name                   = trimprefix(each.value.name, "sg-")
    description            = each.value.description
    vpc_id                 = local.vpc_name_id_map[each.value.vpc_name] <- 이 부분이 에러가 날 것입니다.
    revoke_rules_on_delete = each.value.revoke_rules_on_delete

    tags = {
        Name = each.value.name
    }
    }
    ```
    `Shell`에서의 커맨드를 실행하여 `terraform_remote_state`를 통한 의존성 설정 코드를 생성하겠습니다:

    ```bash
    cd /root/code/terraform/project/sg
    cat  > reference.tf << 'EOF'
    data "terraform_remote_state" "vpc" {
    backend = "local"

    config = {
        path = "../vpc/terraform.tfstate"
    }
    }

    locals {
    vpc_name_id_map = data.terraform_remote_state.vpc.outputs.vpc_name_id_map
    }
    EOF
    ```
    `Shell`에서 `init`과 `plan`을 수행합니다:

    ```bash
    terraform init
    terraform plan
    ```
    `plan` 결과를 검토해 의도한 변경만 포함되는지 확인합니다. 새 리소스가 생성되지 않아야 합니다.

    다음으로 변경 사항을 적용합니다. `apply`를 실행해 import를 실행합니다:

    ```bash
    terraform apply --auto-approve
    ```
    인프라를 import 하면 다음과 같은 출력 결과를 확인할 수있습니다:

    ```bash
    Apply complete! Resources: 2 imported, 0 added, 0 changed, 0 destroyed.
    ```
    > Note
    > 
    > 수행 결과 changed가 출력될 수 있는데, 이것은 일부 attribute의 정합성을 맞추기 위한 것으로, 실제 리소스의 변경을 일으키지 않으니 무시해도 됩니다.

3. EC2 워킹 디렉토리 복원

    EC2 워킹 디렉토리의 main.tf를 보면, subnet_id와 vpc_security_group_ids를 입력받아야 하는 부분이 있는데, SG 워킹 디렉토리의 경우와 유사하게, VPC 워킹 디렉토리 및 SG 워킹 디렉토리와 분리되었기 때문에 별도로 의존성을 설정해주는 단계가 필요합니다.

    참고용 파일/디렉토리 구조:

    ```bash
    resource "aws_instance" "this" {
    instance_type               = var.ec2_instance.instance_type
    key_name                    = var.ec2_instance.key_pair_name
    associate_public_ip_address = var.ec2_instance.associate_public_ip_address
    subnet_id                   = local.subnet_name_id_map[var.ec2_instance.subnet_name]  <- 이 부분이 에러가 날 것입니다.
    vpc_security_group_ids      = [for security_group_name in var.ec2_instance.security_group_name_list : local.security_group_name_id_map[security_group_name]]  <- 이 부분이 에러가 날 것입니다.
    ami                         = data.aws_ami.this.id
    user_data                   = try(templatefile(var.ec2_instance.user_data.template_path, var.ec2_instance.user_data.template_values), null)

    tags = merge({
        Name = var.ec2_instance.name
    }, var.ec2_instance.tag_map)

    lifecycle {
        ignore_changes = [ami]
    }
    }
    ```
    `Shell`에서의 커맨드를 실행하여 `terraform_remote_state`를 통한 의존성 설정 코드를 생성하겠습니다:

    ```bash
    cd /root/code/terraform/project/ec2
    cat  > reference.tf << 'EOF'
    data "terraform_remote_state" "vpc" {
    backend = "local"

    config = {
        path = "../vpc/terraform.tfstate"
    }
    }

    data "terraform_remote_state" "security_group" {
    backend = "local"

    config = {
        path = "../sg/terraform.tfstate"
    }
    }

    locals {
    subnet_name_id_map = data.terraform_remote_state.vpc.outputs.subnet_name_id_map
    security_group_name_id_map = data.terraform_remote_state.security_group.outputs.security_group_name_id_map
    }
    EOF
    ```
    `Shell`에서 `init`과 `plan`을 수행합니다:

    ```bash
    terraform init
    terraform plan
    ```
    `plan` 결과를 검토해 의도한 변경만 포함되는지 확인합니다. 새 리소스가 생성되지 않아야 합니다.

    다음으로 변경 사항을 적용합니다. `apply`를 실행해 import를 실행합니다:

    ```bash
    terraform apply --auto-approve
    ```
    인프라를 import 하면 다음과 같은 출력 결과를 확인할 수있습니다:

    ```bash
    Apply complete! Resources: 1 imported, 0 added, 0 changed, 0 destroyed.
    ```
    > Note
    > 
    > 수행 결과 changed가 출력될 수 있는데, 이것은 일부 attribute의 정합성을 맞추기 위한 것으로, 실제 리소스의 변경을 일으키지 않으니 무시해도 됩니다.

4. import 작업이 완료되었으니 import 파일을들 모두 제거합니다.

    `Shell`에서 다음 명령을 실행합니다:

    ```bash
    cd /root/code/terraform/project
    rm -f vpc/import.tf
    rm -f sg/import.tf
    rm -f ec2/import.tf
    ```

이를 통해 모든 워킹 디렉토리에서 기존 리소스를 성공적으로 import하고 state 파일을 복원했습니다. 각 워킹 디렉토리는 독립적으로 작동하며, terraform_remote_state를 통해 다른 디렉토리의 리소스를 참조할 수 있습니다. 다음 단계에서는 이 참조 방식을 보다 유연한 Datasource 기반으로 전환합니다.

### Step 3: 유연한 리소스 참조 패턴 구현

#### 3.1 Datasource 기반 전환
이 단계는 terraform_remote_state 중심의 참조를 Datasource 기반 이름 참조로 전환해, Terraform 내부·외부 리소스를 한 가지 방식으로 다룰 수 있게 만드는 과정입니다. 이렇게 하면 기존 인프라와 신규 인프라를 점진적으로 통합할 때 참조 일관성과 유연성이 크게 높아집니다. 실습에서는 외부에서 생성한 Security Group을 AWS CLI로 만들고, EC2 설정에서 이를 이름으로 조회하는 Datasource를 적용해 연결합니다. 즉, 외부 리소스를 ID가 아닌 이름으로 참조하는 패턴을 도입해, 내부에서 만든 리소스와 동일한 흐름으로 관리하도록 개선합니다.

`Shell` 탭에서 아래 커맨드를 수행하여 "sg-tfacademy-outside"라는 이름의 새로운 Security Group을 생성합니다:

```bash
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=vpc-tfacademy" --query "Vpcs[0].VpcId" --output text)
aws ec2 create-security-group \
    --group-name "tfacademy-outside" \
    --description "Security group created outside of Terraform" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=sg-tfacademy-outside}]" \
    --no-cli-pager
aws ec2 describe-security-groups --filters "Name=tag:Name, Values=sg-tfacademy-outside" --query "SecurityGroups[0].GroupId" --output text --no-cli-pager
```
성공적으로 Security Group이 생성되었다면 Group ID가 출력됩니다. EC2 인스턴스에서 새롭게 생성된 Security Group을 연결하도록 변수를 수정하겠습니다.

아래 코드를 확인하고 `project/ec2/variables.auto.tfvars` 파일을 동일하게 수정합니다:

```bash
ec2_instance = {
  name                        = "i-tfacademy-bastion"
  instance_type               = "t3.large"
  subnet_name                 = "sbn-tfacademy-public-az1"
  associate_public_ip_address = true
  security_group_name_list    = ["sg-tfacademy-bastion", "sg-tfacademy-outside"] <- 이 부분을 추가해주세요.

  ami_conditions = {
    os           = "amazon-linux-2023"
    architecture = "x86_64"
  }
}
```
현재 EC2 디렉토리의 `reference.tf` 파일은 다른 워킹 디렉토리에서 생성한 리소스(Subnet, SecurityGroup)를 `terraform_remote_state`로 직접 참조하도록 구성되어 있습니다. 이러한 방식을 Datasource를 통해 간접적으로 참조할 수 있도록 변경하여 더 유연한 구조를 만들어보겠습니다.

다음 커맨드를 실행하면 기존 `reference.tf` 파일을 백업하고 새로운 data source 기반 참조 로직을 생성합니다:

```bash
cd /root/code/terraform/project/ec2
mv reference.tf reference.tf.bak
cat > reference.tf << 'EOF'
data "aws_subnet" "these" {
  for_each = toset([var.ec2_instance.subnet_name])

  filter {
    name   = "tag:Name"
    values = [each.key]
  }
}

data "aws_security_group" "these" {
  for_each = toset(var.ec2_instance.security_group_name_list)

  name = trimprefix(each.key, "sg-")
}

locals {
  subnet_name_id_map         = { for subnet_name, subnet in data.aws_subnet.these : subnet_name => subnet.id }
  security_group_name_id_map = { for sg_name, sg in data.aws_security_group.these : sg_name => sg.id }
}
EOF
```
새로운 data source 기반 참조 로직이 정상적으로 동작하는지 확인해보겠습니다. EC2 인스턴스는 Terraform 외부에서 생성된 Security Group도 이름으로 참조할 수 있습니다.

`Shell` 탭에서 `init`과 `plan`을 수행합니다: EC2 인스턴스에 새로운 Security Group을 연결하겠습니다:

```bash
terraform init
terraform plan
```
`plan` 결과를 검토해 의도한 변경만 포함되는지 확인합니다. EC2 인스턴스의 `vpc_security_group_ids`에 새로운 Security Group이 추가되어야 합니다.

다음으로 변경 사항을 적용합니다. `apply`를 실행해 변경사항을 적용합니다:

```bash
terraform apply --auto-approve
```
변경사항을 적용하면 다음과 같은 출력 결과를 확인할 수 있습니다.(주요 내용만 표시하였습니다):

```bash
Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  ~ update in-place

Terraform will perform the following actions:

  # aws_instance.this will be updated in-place
  ~ resource "aws_instance" "this" {
      ~ vpc_security_group_ids               = [
          + "sg-0e41943ccb3a6d9a7",
    }

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```
이를 통해 terraform_remote_state 방식에서 Datasource 기반 참조 방식으로 성공적으로 전환했습니다. EC2 인스턴스는 Terraform 내부에서 생성한 리소스와 외부에서 생성한 리소스를 모두 이름으로 참조할 수 있습니다. 다음 단계에서는 이 개념을 확장하여 하이브리드 참조 패턴을 구현해보겠습니다.

#### 3.2 Hybrid 참조 패턴
이 단계에서는 하이브리드 참조 패턴을 구현합니다. 단일 `apply` 런타임 동안 새로 생성되는 리소스는 아직 프로바이더에 존재하지 않기 때문에 Datasource로 조회할 수 없습니다. 따라서 런타임 중에 생성되는 리소스 의존성은 직접 참조(리소스 주소 기반)로 안전하게 해결하고, 런타임 이전에 생성한 리소스(이전 실행에서 만들었거나 Terraform 외부에서 이미 존재)는 Datasource(이름 기반)로 유연하게 가져오는 혼합 방식이 필요합니다. 이 패턴은 리소스 생성 시점을 사용자가 신경쓰지 않더라도 런타임 중 리소스 참조 실패가 발생하지 않도록 하여 안정성을 크게 높여 줍니다.

실습 환경에서 SG 워킹 디렉토리에서는 Security Group 자체를 만들고, 이를 참조하는 Rule도 정의하고 있습니다. 여기서 런타임 중에 생성되는 Security Group은 직접 참조로 연결하고, 이미 존재하는 Security Group은 Datasource를 통한 이름 기반 조회를 적용해 단일 실행에서 두 참조 방식을 병행합니다.

하이브리드 참조 패턴을 테스트하기 위해 다음과 같은 시나리오를 구현하겠습니다:

- Terraform 내부에서 생성하는 "sg-tfacademy-inside" Security Group
- Terraform 외부에서 생성한 "sg-tfacademy-outside" Security Group (Step 1에서 이미 생성)
- 위 두 Security Group을 모두 참조하는 "sg-tfacademy-reference-test" Security Group
아래 코드를 참고하여 `project/sg/variables.auto.tfvars` 파일을 수정하겠습니다:

```bash
security_group_list = [
  {
    name        = "sg-tfacademy-bastion"
    description = "Security Group for bastion instance"
    vpc_name    = "vpc-tfacademy"

    ingress_rule_list = []
    egress_rule_list = [
      { protocol = "all", from_port = "1", to_port = "65535", target_list = ["0.0.0.0/0"], description = "all outbound" },
    ]
  }, <- 이 쉼표를 추가해주십시오.
  ### 여기부터
  {
    name        = "sg-tfacademy-inside"
    description = "Security group created inside of Terraform"
    vpc_name    = "vpc-tfacademy"

    ingress_rule_list = []
    egress_rule_list = [
      { protocol = "all", from_port = "1", to_port = "65535", target_list = ["0.0.0.0/0"], description = "all outbound" },
    ]
  },
  {
    name        = "sg-tfacademy-reference-test"
    description = "Security group for Reference testing"
    vpc_name    = "vpc-tfacademy"

    ingress_rule_list = [
      { protocol = "all", from_port = "1", to_port = "65535", target_list = ["sg-tfacademy-inside"], description = "referencing inside sg" },
      { protocol = "all", from_port = "1", to_port = "65535", target_list = ["sg-tfacademy-outside"], description = "referencing outside sg" }
    ]
    egress_rule_list = [
      { protocol = "all", from_port = "1", to_port = "65535", target_list = ["0.0.0.0/0"], description = "all outbound" },
    ]
  }
  ### 여기까지 코드를 추가합니다
]
```
하이브리드 참조 로직을 구현하기 위해 Security Group의 main.tf 파일을 수정해야 합니다.

`project/sg/main.tf`에서 다음의 코드 조각을 찾아 주석처리합니다:

```bash
# locals {
#   security_group_name_id_map = { for key, security_group in local.security_group_map : security_group.name => aws_security_group.these[key].id }
# }
```
그리고 아래의 코드를 가장 마지막에 추가합니다. 이 로직은 Terraform에서 런타임 중 생성하는 Security Group과 사전에 생성한 Security Group을 모두 처리할 수 있습니다:

```bash
locals {
  tf_created_security_group_name_id_map = { for key, security_group in local.security_group_map : security_group.name => aws_security_group.these[key].id }
  tf_created_security_group_name_list   = keys(local.tf_created_security_group_name_id_map)
  required_security_group_name_list     = compact(distinct([for security_group_rule in local.security_group_rule_map : security_group_rule.source_security_group_name]))
  searching_security_group_name_list    = setsubtract(local.required_security_group_name_list, local.tf_created_security_group_name_list)
}

data "aws_security_group" "these" {
  for_each = toset(local.searching_security_group_name_list)

  name = trimprefix(each.key, "sg-")
}

locals {
  searched_security_group_name_id_map = { for security_group_name, security_group in data.aws_security_group.these : security_group_name => security_group.id }
  security_group_name_id_map          = merge(local.tf_created_security_group_name_id_map, local.searched_security_group_name_id_map)
}
```
코드 맥락상 중간에 위치하는 것이 더 자연스럽지만 Terraform은 코드의 순서와 관계없이 동작하기 때문에 실습의 편의상 가장 마지막에 추가하겠습니다.

하이브리드 참조 로직이 정상적으로 동작하는지 확인해보겠습니다. 새로운 Security Group들이 생성되고 서로 다른 방식으로 참조되는 것을 확인할 수 있습니다.

`Shell` 탭에서 `init`과 `plan`을 수행합니다:

```bash
cd /root/code/terraform/project/sg
terraform init
terraform plan
```
`plan` 결과를 검토해 의도한 변경만 포함되는지 확인합니다. 코드가 작동하는지 확인한 후 아래의 `apply` 명령어를 실행합니다:

```bash
terraform apply --auto-approve
```
실행하면 다음과 같은 출력 결과를 확인할 수 있습니다.(중요한 정보만 포함하였습니다):

```bash
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

security_groups = {
  ...
  "sg_tfacademy_reference_test" = {
    "arn" = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-..."
    "ingress" = toset([
      {
        "description" = "referencing inside sg"
        "from_port" = 0
        "protocol" = "-1다
        "security_groups" = toset([
          "sg-02f87231ee9928f62",
        ])
        "to_port" = 0
      },
      {
        "description" = "referencing outside sg"
        "from_port" = 0
        "protocol" = "-1"
        "security_groups" = toset([
          "sg-0e41943ccb3a6d9a7",
        ])
        "to_port" = 0
      },
    ])
  }
}
```
> Note
> 
> 간혹 apply를 한번 더 실행하여야 output 결과가 모두 표시되는 경우가 있습니다. 위와 같은 결과가 정상적으로 표시되지 않는다면 apply 명령을 한번 더 실행하십시오.

하이브리드 참조 패턴을 통해 리소스 생성 시점을 따로 신경 쓰지 않아도 런타임 참조 이슈를 사전에 차단하고 일관된 실행을 달성했습니다. 다음 단계에서는 이러한 워킹 디렉토리 구조를 재사용 가능한 모듈 구조로 전환하여 코드의 재사용성을 향상시키겠습니다.

### Step 4: 모듈화 아키텍처로의 진화

#### 4.1 Module 구조 생성
이 단계에서는 코드 재사용성과 유지보수성을 강화하기 위해 모듈 기반 아키텍처로 진화하는 과정입니다. 기존 워킹 디렉토리를 모듈로 변환하고 Import 마이그레이션을 수행하여 안정적인 모듈 구조를 구축합니다. 모듈화를 통해 코드의 재사용성을 향상시키고, 다양한 환경에서 동일한 로직을 일관되게 적용할 수 있습니다. 또한 모듈의 버전 관리를 통해 안정적인 인프라 관리가 가능합니다.

현재 VPC, Security Group, EC2 Instance가 각각 분리된 워킹 디렉토리로 구성되어 있습니다. 이 구조를 Module 기반 구조로 전환하기위해 Module Directory를 생성하고 기존 Code를 복사합니다. Module Directory에서 필요한 Code는 `.tf` 파일만 해당됩니다.

`Shell`에서 다음 명령을 실행합니다:

```bash
cd /root/code/terraform
mkdir module
mkdir module/vpc
mkdir module/ec2
mkdir module/sg
cp project/vpc/*.tf module/vpc/
cp project/ec2/*.tf module/ec2/
cp project/sg/*.tf module/sg/
```
수행 뒤 파일 구조는 다음과 유사해야 합니다:

```bash
terraform
├── module    <- 새롭게 추가된 Module 디렉토리
│   ├── ec2
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── reference.tf
│   │   └── variables.tf
│   ├── sg
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── reference.tf
│   │   └── variables.tf
│   └── vpc
│       ├── main.tf
│       ├── outputs.tf
│       └── variables.tf
├── project
└── project-old
```
#### 4.2 Module 구조 전환을 위한 import 준비
이 단계에서는 기존 리소스를 새로운 state 파일로 안전하게 보존하기 위한 import 준비 과정입니다. Module로 전환하기 전에 기존 Resource들을 새로운 Module 구조로 import하기 위한 준비 작업을 수행합니다. 각 워킹 디렉토리에서 Module 경로를 포함한 import 파일을 생성해야 합니다.

`Shell`에서 다음 명령을 실행합니다:

```bash
cd /root/code/terraform/project/vpc
mkdir imports
cat > imports/import.tftpl << 'EOF'
%{ for resource in resources ~}
import {
  to = ${resource.to}
  id = "${resource.id}"
}

%{ endfor ~}
EOF
cp -r imports ../sg
cp -r imports ../ec2
```
수행 결과 파일 구조는 다음과 같습니다. `Code` 탭에서 파일 구조를 확인하세요:

```bash
terraform
├── module
├── project
│   ├── ec2
│   │   ├── imports
│   │       └── import.tftpl  <- 새롭게 추가된 import template 파일
│   ├── sg
│   │   ├── imports
│   │       └── import.tftpl  <- 새롭게 추가된 import template 파일
│   └── vpc
│       ├── imports
│           └── import.tftpl  <- 새롭게 추가된 import template 파일
```
각 워킹 디렉토리에서 Module 경로를 포함한 import 파일을 생성합니다. 기존 Resource들이 새로운 Module 구조에서 정상적으로 import되도록 Module 경로를 포함해야 합니다.

`Shell`에서 다음 명령을 실행합니다:

```bash
cd /root/code/terraform/project/vpc
cat > generate-imports.tf << 'EOF'
locals {
  vpc_import_list = [{
    to = "module.vpc.aws_vpc.this"
    id = aws_vpc.this.id
  }]

  subnet_import_list = [for key, subnet in aws_subnet.these : {
    to = "module.vpc.aws_subnet.these[\"${key}\"]"
    id = subnet.id
  }]

  internet_gateway_import_list = [{
    to = "module.vpc.aws_internet_gateway.this"
    id = aws_internet_gateway.this.id
  }]

  eip_import_list = [for key, eip in aws_eip.these : {
    to = "module.vpc.aws_eip.these[\"${key}\"]"
    id = eip.id
  }]

  nat_gateway_import_list = [for key, nat_gateway in aws_nat_gateway.these : {
    to = "module.vpc.aws_nat_gateway.these[\"${key}\"]"
    id = nat_gateway.id
  }]

  route_table_import_list = [for key, route_table in aws_route_table.these : {
    to = "module.vpc.aws_route_table.these[\"${key}\"]"
    id = route_table.id
  }]

  route_table_association_import_list = [for key, route_table_association in aws_route_table_association.these : {
    to = "module.vpc.aws_route_table_association.these[\"${key}\"]"
    id = "${route_table_association.subnet_id}/${route_table_association.route_table_id}"
  }]

  route_import_list = [for key, route in aws_route.these : {
    to = "module.vpc.aws_route.these[\"${key}\"]"
    id = "${route.route_table_id}_${route.destination_cidr_block}"
  }]
}

resource "local_file" "import_vpc" {
  filename = "${path.module}/imports/import.tf"
  content = templatefile("${path.module}/imports/import.tftpl", {
    resources = concat(
      local.vpc_import_list,
      local.subnet_import_list,
      local.internet_gateway_import_list,
      local.eip_import_list,
      local.nat_gateway_import_list,
      local.route_table_import_list,
      local.route_table_association_import_list,
      local.route_import_list
    )
  })
}
EOF

cd /root/code/terraform/project/sg
cat > generate-imports.tf << 'EOF'
locals {
  security_group_import_list = [for key, security_group in aws_security_group.these : {
    to = "module.security_groups.aws_security_group.these[\"${key}\"]"
    id = security_group.id
  }]

  security_group_rule_import_list = [for key, security_group_rule in aws_security_group_rule.these : {
    to = "module.security_groups.aws_security_group_rule.these[\"${key}\"]"
    id = (security_group_rule.cidr_blocks != null
      ? "${security_group_rule.security_group_id}_${security_group_rule.type}_${security_group_rule.protocol}_${security_group_rule.from_port}_${security_group_rule.from_port}_${security_group_rule.cidr_blocks[0]}"
      : "${security_group_rule.security_group_id}_${security_group_rule.type}_${security_group_rule.protocol}_${security_group_rule.from_port}_${security_group_rule.from_port}_${security_group_rule.source_security_group_id}"
    )
  }]
}

resource "local_file" "import_security_group" {
  filename = "${path.module}/imports/import.tf"
  content = templatefile("${path.module}/imports/import.tftpl", {
    resources = concat(
      local.security_group_import_list,
      local.security_group_rule_import_list,
    )
  })
}
EOF

cd /root/code/terraform/project/ec2
cat > generate-imports.tf << 'EOF'
locals {
  ec2_instance_import_list = [{
    to = "module.ec2_instance.aws_instance.this"
    id = aws_instance.this.id
  }]
}

resource "local_file" "import_ec2_instance" {
  filename = "${path.module}/imports/import.tf"
  content = templatefile("${path.module}/imports/import.tftpl", {
    resources = concat(
      local.ec2_instance_import_list
    )
  })
}
EOF
```
각 워킹 디렉토리에서 import 파일을 생성합니다.

`Shell`에서 다음 명령을 실행합니다:

```bash
cd /root/code/terraform/project/vpc
terraform init
terraform apply -auto-approve
cd /root/code/terraform/project/sg
terraform init
terraform apply -auto-approve
cd /root/code/terraform/project/ec2
terraform init
terraform apply -auto-approve
```
수행 결과 파일 구조는 다음과 같습니다. `Code` 탭에서 파일 구조를 확인하세요:

```bash
terraform
├── module
├── project
│   ├── ec2
│   │   ├── generate-imports.tf <- 새롭게 추가된 import 생성 파일
│   │   ├── imports
│   │       ├── import.tf <- 새롭게 추가된 import 파일
│   │       └── import.tftpl
│   ├── sg
│   │   ├── generate-imports.tf <- 새롭게 추가된 import 생성 파일
│   │   ├── imports
│   │       ├── import.tf <- 새롭게 추가된 import 파일
│   │       └── import.tftpl
│   └── vpc
│       ├── generate-imports.tf <- 새롭게 추가된 import 생성 파일
│       ├── imports
│           ├── import.tf <- 새롭게 추가된 import 파일
│           └── import.tftpl
```
#### 4.3 Module 기반 프로젝트 전환
기존 워킹 디렉토리를 Module을 사용하는 새로운 구조로 전환합니다. 각 워킹 디렉토리는 해당 Module을 호출하는 간단한 구조가 됩니다. 기존 Project를 백업하고 새로운 Module 기반 Project 구조를 생성하겠습니다. Variable 파일과 import 파일을 새로운 Project 디렉토리로 복사합니다.

`Shell`에서 다음 명령을 실행합니다:

```bash
cd /root/code/terraform
mv project project-old2
mkdir project
mkdir project/vpc
mkdir project/sg
mkdir project/ec2
cp project-old2/vpc/variables.tf project/vpc/
cp project-old2/sg/variables.tf project/sg/
cp project-old2/ec2/variables.tf project/ec2/
cp project-old2/vpc/variables.auto.tfvars project/vpc/
cp project-old2/sg/variables.auto.tfvars project/sg/
cp project-old2/ec2/variables.auto.tfvars project/ec2/
cp project-old2/vpc/imports/import.tf project/vpc/
cp project-old2/sg/imports/import.tf project/sg/
cp project-old2/ec2/imports/import.tf project/ec2/
```
수행 결과 파일 구조는 다음과 같습니다. `Code` 탭에서 파일 구조를 확인하세요:

```bash
terraform
├── module
├── project  <- 새롭게 생성된 Module 기반 Project 디렉토리
│   ├── ec2
│   │   ├── import.tf
│   │   ├── variables.auto.tfvars
│   │   └── variables.tf
│   ├── sg
│   │   ├── import.tf
│   │   ├── variables.auto.tfvars
│   │   └── variables.tf
│   └── vpc
│       ├── import.tf
│       ├── variables.auto.tfvars
│       └── variables.tf
├── project-old
└── project-old2  <- 백업된 기존 Project 디렉토리
```

1. VPC 워킹 디렉토리를 Module을 사용하는 구조로 변경합니다. 기존의 직접적인 Resource 정의 대신 Module을 호출하는 방식으로 전환합니다.

    Module을 호출하는 구문을 포함한 새로운 `main.tf` 및 `outputs.tf` 파일을 생성합니다.

    `Shell`에서 다음 명령을 실행합니다:

    ```bash
    cd /root/code/terraform/project/vpc
    cat > main.tf << 'EOF'
    module "vpc" {
    source = "../../module/vpc"

    vpc              = var.vpc
    subnet_list      = var.subnet_list
    internet_gateway = var.internet_gateway
    nat_gateway_list = var.nat_gateway_list
    route_table_list = var.route_table_list
    }
    EOF

    cat > outputs.tf << 'EOF'
    output "vpc" {
    value = module.vpc
    }
    EOF
    ```
    수행 결과 파일 구조는 다음과 같습니다. `Code` 탭에서 파일 구조를 확인하세요:

    ```bash
    preject
    ├── ec2
    ├── sg
    └── vpc
        ├── import.tf
        ├── main.tf  <- 새롭게 추가된 파일
        ├── outputs.tf  <- 새롭게 추가된 파일
        ├── variables.auto.tfvars
        └── variables.tf
    ```
    "VPC Module"이 정상적으로 동작하는지 확인하겠습니다.

    `Shell` 탭에서 `init`과 `plan`을 수행합니다:

    ```bash
    terraform init
    terraform plan
    ```
    `plan` 결과를 확인하여 기존 VPC Resource들이 Module 구조로 정상적으로 import되는지 검토하세요. 새로운 Resource가 생성되지 않고 기존 Resource들만 import되어야 합니다.

    다음 `apply` 커맨드를 실행합니다:

    ```bash
    terraform apply --auto-approve
    ```
    "VPC Module" 적용이 완료되면 다음과 같은 출력을 확인할 수 있습니다.:

    ```bash
    Apply complete! Resources: 16 imported, 0 added, 0 changed, 0 destroyed.
    ```
2. Security Group 모듈 적용

    Security Group 워킹 디렉토리를 Module 기반으로 전환합니다. Module에서 VPC 정보를 Datasource로 조회하도록 수정해야 합니다.

    Module을 호출하는 구문을 포함한 새로운 `main.tf` 및 `outputs.tf` 파일을 생성합니다.

    `Shell`에서 다음 명령을 실행합니다:

    ```bash
    cd /root/code/terraform/project/sg
    cat > main.tf << 'EOF'
    module "security_groups" {
    source = "../../module/sg"

    security_group_list = var.security_group_list
    }
    EOF

    cat > outputs.tf << 'EOF'
    output "security_groups" {
    value = module.security_groups
    }
    EOF
    ```
    Security Group 워킹 디렉토리는 아직 VPC 정보를 조회할 때 "terraform_remote_state" Datasource를 이용하는 직접 참조 로직을 가지고있습니다. 이를 Datasource로 조회하는 간접 참조 로직으로 수정하겠습니다.

    `Shell`에서 다음 명령을 실행합니다:

    ```bash
    cd /root/code/terraform/module/sg
    mv reference.tf reference.tf.bak
    cat > reference.tf << 'EOF'
    locals {
    required_vpc_name_list = compact(var.security_group_list[*].vpc_name)
    }

    data "aws_vpc" "these" {
    for_each = toset(local.required_vpc_name_list)

    filter {
        name   = "tag:Name"
        values = [each.key]
    }
    }

    locals {
    vpc_name_id_map = { for vpc_name, vpc in data.aws_vpc.these : vpc_name => vpc.id }
    }
    EOF
    ```
    수행 결과 파일 구조는 다음과 같습니다. `Code` 탭에서 파일 구조를 확인하세요:

    ```bash
    module
    ├── ec2
    ├── sg
    │   ├── main.tf
    │   ├── outputs.tf
    │   ├── reference.tf  <- 새롭게 추가된 파일
    │   ├── reference.tf.bak  <- 기존 파일 백업
    │   └── variables.tf
    └── vpc
    ```
    Module이 정상적으로 동작하는지 확인하겠습니다.

    `Shell` 탭에서 `init`과 `plan`을 수행합니다:

    ```bash
    cd /root/code/terraform/project/sg
    terraform init
    terraform plan
    ```
    `plan` 결과를 확인하여 기존 Security Group Resource들이 Module 구조로 정상적으로 import되는지 검토하세요.

    `Shell`에서 다음 명령을 실행합니다:

    ```bash
    terraform apply --auto-approve
    ```
    Security Group Module 적용이 완료되면 다음과 같은 출력을 확인할 수 있습니다.:

    ```bash
    Apply complete! Resources: 8 imported, 0 added, 0 changed, 0 destroyed.
    ```
3. EC2 모듈 적용

    마지막으로 EC2 워킹 디렉토리를 Module 기반으로 전환합니다.

    Module을 호출하는 구문을 포함한 새로운 `main.tf` 및 `outputs.tf` 파일을 생성합니다.

    `Shell`에서 다음 명령을 실행합니다:

    ```bash
    cd /root/code/terraform/project/ec2
    cat > main.tf << 'EOF'
    module "ec2_instance" {
    source = "../../module/ec2"

    ec2_instance = var.ec2_instance
    }
    EOF

    cat > outputs.tf << 'EOF'
    output "ec2_instance" {
    value = module.ec2_instance
    }
    EOF
    ```
    EC2 Module은 이미 VPC와 Security Group 정보를 Datasource로 조회할 수 있도록 설정되었습니다. Reference 로직을 수정할 필요가 없습니다.

    수행 결과 파일 구조는 다음과 같습니다. `Code` 탭에서 파일 구조를 확인하세요:

    ```bash
    project
    ├── ec2
    │   ├── import.tf
    │   ├── main.tf  <- 새롭게 추가된 파일
    │   ├── outputs.tf  <- 새롭게 추가된 파일
    │   ├── variables.auto.tfvars
    │   └── variables.tf
    ├── sg
    └── vpc
    ```
    Module이 정상적으로 동작하는지 확인하겠습니다.

    `Shell` 탭에서 `init`과 `plan`을 수행합니다:

    ```bash
    terraform init
    terraform plan
    ```
    `plan` 결과를 확인하여 기존 EC2 Instance가 Module 구조로 정상적으로 import되는지 검토하세요.

    `Shell`에서 다음 명령을 실행합니다:

    ```bash
    terraform apply --auto-approve
    ```
    EC2 Module 적용이 완료되면 다음과 같은 출력을 확인할 수 있습니다.:

    ```bash
    Apply complete! Resources: 1 imported, 0 added, 0 changed, 0 destroyed.
    ```

모든 Module 전환 작업이 완료되었으니 임시로 사용했던 import 파일들을 제거합니다.

`Shell`에서 다음 명령을 실행합니다:

```bash
cd /root/code/terraform/project
rm -f vpc/import.tf
rm -f sg/import.tf
rm -f ec2/import.tf
```
이 단계에서는 기존 워킹 디렉토리 구조를 재사용 가능한 모듈 기반 아키텍처로 성공적으로 전환했습니다. 이를 통해 코드의 재사용성을 향상시키고 안정적인 확장 구조를 달성하였습니다.

### Step 5: 공통 로직의 추상화

이 단계에서는 현재 Module 기반 구조에서 한 단계 더 나아가 공통 Logic을 Function Module로 추상화하여 복잡한 로직의 호출을 간소화시켜 코드 일관성과 효율성을 향상시켜보겠습니다.

본 실습에서는 Security Group ID 조회 Logic을 Function Module로 구현합니다.

`Shell`에서 다음 명령을 실행합니다:

```bash
cd /root/code/terraform
mkdir function
mkdir function/get-resource-id
cat > function/get-resource-id/get-security-group-id.tf << 'EOF'
variable "required_security_group_name_list" { default = [] }
variable "tf_created_security_group_name_id_map" { default = {} }

locals {
  required_security_group_name_list   = var.required_security_group_name_list
  tf_created_security_group_name_list = keys(var.tf_created_security_group_name_id_map)
  searching_security_group_name_list  = setsubtract(local.required_security_group_name_list, local.tf_created_security_group_name_list)
}

data "aws_security_group" "these" {
  for_each = toset(local.searching_security_group_name_list)

  name = trimprefix(each.key, "sg-")
}

locals {
  searched_security_group_name_id_map = { for security_group in data.aws_security_group.these : security_group.tags.Name => security_group.id }
  security_group_name_id_map          = merge(var.tf_created_security_group_name_id_map, local.searched_security_group_name_id_map)
}

output "security_group_name_id_map" {
  value = local.security_group_name_id_map
}
EOF
```
수행 결과 파일 구조는 다음과 같습니다. `Code` 탭에서 파일 구조를 확인하세요:

```bash
terraform
├── function  <- 새롭게 추가된 Function Module 디렉토리
│   └── get-resource-id
│       └── get-security-group-id.tf
├── module
├── project
├── project-old
└── project-old2
```
Security Group Module에서 기존의 동일한 Logic을 제거하고 새로 생성한 Function Module을 사용하도록 수정합니다.

`module/sg/main.tf`에서 마지막에 추가되었던 기존의 Security Group ID 조회 Logic을 주석처리합니다:

```bash
# locals {
#   tf_created_security_group_name_id_map = { for key, security_group in local.security_group_map : security_group.name => aws_security_group.these[key].id }
#   tf_created_security_group_name_list   = keys(local.tf_created_security_group_name_id_map)
#   required_security_group_name_list     = compact(distinct([for security_group_rule in local.security_group_rule_map : security_group_rule.source_security_group_name]))
#   lookup_security_group_name_list       = setsubtract(local.required_security_group_name_list, local.tf_created_security_group_name_list)
# }

# data "aws_security_group" "these" {
#   for_each = toset(local.lookup_security_group_name_list)

#   filter {
#     name   = "tag:Name"
#     values = [each.key]
#   }
# }

# locals {
#   lookup_security_group_name_id_map = { for security_group_name, security_group in data.aws_security_group.these : security_group_name => security_group.id }
#   security_group_name_id_map        = merge(local.tf_created_security_group_name_id_map, local.lookup_security_group_name_id_map)
# }
```
그리고 동일한 파일의 마지막에 Function Module을 호출하는 Code를 추가합니다:

```bash
module "get_resource_id" {
  source = "../../function/get-resource-id"

  required_security_group_name_list     = compact(distinct([for security_group_rule in local.security_group_rule_map : security_group_rule.source_security_group_name]))
  tf_created_security_group_name_id_map = { for key, security_group in local.security_group_map : security_group.name => aws_security_group.these[key].id }
}

locals {
  security_group_name_id_map = module.get_resource_id.security_group_name_id_map
}
```
Security Group Module이 Function Module을 사용하도록 수정되었습니다. 재사용 가능한 Function을 통해 Security Group ID를 조회할 수 있습니다.

코드가 정상적으로 동작하는지 확인하겠습니다.

`Shell` 탭에서 `init`과 `plan`을 수행합니다:

```bash
cd /root/code/terraform/project/sg
terraform init
terraform plan
```
`plan` 결과를 확인하여 새로운 리소스의 변경 없이 통과되는지 확인하세요. 이후 다음 `apply` 커맨드를 실행합니다:

```bash
terraform apply --auto-approve
```
다음과 같은 출력을 확인할 수 있습니다.:

```bash
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration and found no differences, so no changes are needed.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```
이 단계에서는 공통 로직을 Function Module로 추상화하여 코드의 재사용성과 일관성을 크게 향상시켰습니다.

### Step 6: 복합 워킹 디렉토리 패턴 적용

이 단계에서는 서로 강하게 연관된 리소스를 하나의 워킹 디렉토리에서 통합 관리하는 고급 패턴을 다룹니다. EC2와 Security Group을 함께 관리함으로써 의존성을 단순화하고 배포 효율성을 높일 수 있습니다. 이렇게 밀접히 관련된 Resource들을 하나의 워킹 디렉토리에서 함께 관리하는 복합 구조를 생성합니다. EC2 Instance와 Security Group을 함께 배포하여 Dependency를 단순화하고 배포 효율성을 향상시킵니다.

Workload Instance를 위한 새로운 워킹 디렉토리를 생성합니다. 이 Directory에서는 EC2 Instance와 해당 Security Group을 함께 관리합니다.

`Shell`에서 다음 명령을 실행합니다:

```bash
cd /root/code/terraform/project
mkdir ec2-workload
cp ec2/main.tf ec2-workload/main-ec2.tf
cp sg/main.tf ec2-workload/main-sg.tf
cp ec2/variables.tf ec2-workload/variables-ec2.tf
cp sg/variables.tf ec2-workload/variables-sg.tf
cp ec2/outputs.tf ec2-workload/outputs-ec2.tf
cp sg/outputs.tf ec2-workload/outputs-sg.tf
```
Workload Instance를 위한 TF Vars 파일을 생성합니다. 이 Workload Instance는 Private Subnet에 배치되며 Bastion Instance로부터의 `SSH` 접근만 허용합니다.

`Shell`에서 다음 명령을 실행합니다:

```bash
cd /root/code/terraform/project/ec2-workload
cat > variables-ec2.auto.tfvars << 'EOF'
ec2_instance = {
  name                        = "i-tfacademy-workload"
  instance_type               = "t3.large"
  subnet_name                 = "sbn-tfacademy-private-az1"
  associate_public_ip_address = false
  security_group_name_list    = ["sg-tfacademy-workload"]

  ami_conditions = {
    os           = "amazon-linux-2023"
    architecture = "x86_64"
  }
}
EOF
cat > variables-sg.auto.tfvars << 'EOF'
security_group_list = [
  {
    name        = "sg-tfacademy-workload"
    description = "Security Group for workload instance"
    vpc_name    = "vpc-tfacademy"

    ingress_rule_list = [
      { protocol = "all", from_port = "22", to_port = "22", target_list = ["sg-tfacademy-bastion"], description = "ssh inbound from bastion instance" }
    ]
    egress_rule_list = [
      { protocol = "all", from_port = "1", to_port = "65535", target_list = ["0.0.0.0/0"], description = "all outbound" },
    ]
  }
]
EOF
```
수행 결과 파일 구조는 다음과 같습니다. `Code` 탭에서 파일 구조를 확인하세요:

```bash
terraform
├── function
├── module
├── project
│   ├── ec2
│   ├── ec2-workload  <- 새롭게 추가된 복합 워킹 디렉토리
│   │   ├── main-ec2.tf
│   │   ├── main-sg.tf
│   │   ├── outputs-ec2.tf
│   │   ├── outputs-sg.tf
│   │   ├── variables-ec2.auto.tfvars
│   │   ├── variables-ec2.tf
│   │   ├── variables-sg.auto.tfvars
│   │   └── variables-sg.tf
│   ├── sg
│   └── vpc
└── project-old2
```
워킹 디렉토리에서 Security Group과 EC2 Instance 간의 의존성을 정상적으로 설정하려면, Security Group Module을 생성한 후 EC2 Instance Module을 생성해야 합니다. 중요한 점은 Security Group Module에서 생성된 Security Group을 EC2 Module에서 동일한 apply 실행 중에는 Datasource로 참조할 수 없다는 것입니다. 따라서 Security Group Module에서 생성된 리소스 정보를 EC2 Module로 직접 전달하는 방법을 사용해야 합니다.

`project/ec2-workload/main-sg.tf`의 마지막에 Security Group Module에서 생성된 리소스를 추출하는 다음의 코드를 추가합니다:

```bash
locals {
  security_group_name_id_map = { for security_group in module.security_groups.security_groups : security_group.tags.Name => security_group.id }
}
```
`project/ec2-workload/main-ec2.tf`에 다음과 같이 "tf_created_security_group_name_id_map" attribute를 추가하여 Runtime 중 생성되는 Security Group 정보를 전달합니다:

```bash
module "ec2_instance" {
  source = "../../module/ec2"

  ec2_instance = var.ec2_instance

  tf_created_security_group_name_id_map = local.security_group_name_id_map   <- 이 항목을 추가합니다.
}
```
EC2 Module이 Security Group 정보를 받을 수 있도록 Variable을 추가합니다.

`module/ec2/variables.tf`의 마지막에 다음의 코드를 추가합니다.

다음 내용을 확인합니다:

```bash
variable "tf_created_security_group_name_id_map" {
  description = "Name-ID map of SecurityGroup create by Terraform"
  type        = map(string)
  default     = {}
}
```
그리고 앞에서 생성하였던 Security Group ID 조회 Function Module을 이용하도록 EC2 Module을 개선합니다.

`Shell`에서 다음 명령을 실행합니다:

```bash
cd /root/code/terraform/module/ec2
cp reference.tf reference.tf.bak
cat > reference.tf << 'EOF'
data "aws_subnet" "these" {
  for_each = toset([var.ec2_instance.subnet_name])

  filter {
    name   = "tag:Name"
    values = [each.key]
  }
}

module "get_resource_id" {
  source = "../../function/get-resource-id"

  required_security_group_name_list     = var.ec2_instance.security_group_name_list
  tf_created_security_group_name_id_map = var.tf_created_security_group_name_id_map
}

locals {
  subnet_name_id_map         = { for subnet_name, subnet in data.aws_subnet.these : subnet_name => subnet.id }
  security_group_name_id_map = module.get_resource_id.security_group_name_id_map
}
EOF
```
EC2 Module의 Reference Logic이 업데이트되어 Function Module을 통해 Security Group 정보를 조회할 수 있게 되었습니다. 복합 워킹 디렉토리에서 Infrastructure를 배포할 준비가 완료되었습니다.

코드가 정상적으로 동작하는지 확인하겠습니다.

`Shell` 탭에서 `init`과 `plan`을 수행합니다:

```bash
cd /root/code/terraform/project/ec2-workload
terraform init
terraform plan
```
`plan` 결과를 확인하여 새로운 Workload Instance와 Security Group이 생성되는지 검토하세요. 새로운 Resource들이 정상적으로 계획되었다면 다음 `apply` 커맨드를 실행합니다:

```bash
terraform apply --auto-approve
```
고급 모듈화 구조 적용이 완료되면 다음과 같은 출력을 확인할 수 있습니다.:

```bash
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```
이 단계에서는 복합 워킹 디렉토리 패턴을 통해 밀접하게 연관된 리소스들을 하나의 워킹 디렉토리에서 통합 관리하는 고급 구조를 구현했습니다.

### 실습 완료

축하합니다! 본 실습을 통해 Terraform의 고급 아키텍처 설계 기법을 단계별로 학습하고 실제 AWS 환경에서 적용해보았습니다.

실습에서 다룬 주요 내용을 정리하면 다음과 같습니다:

- 단일 구조에서 시작: 모든 리소스가 하나의 state 파일에서 관리되는 기본 구조 이해
- 독립 워킹 디렉토리 전환: VPC, Security Group, EC2를 각각 독립적인 워킹 디렉토리로 분리하여 팀별 독립 작업 환경 구성
- 유연한 리소스 참조: terraform_remote_state에서 Datasource 기반 참조로 전환하고 하이브리드 참조 패턴 구현
- 모듈화 아키텍처: 기존 워킹 디렉토리를 재사용 가능한 모듈 구조로 전환하여 코드 재사용성 향상
- 공통 로직 추상화: Function Module을 통한 공통 로직 추상화로 코드 일관성과 효율성 달성
- 복합 워킹 디렉토리: 밀접하게 연관된 리소스들을 통합 관리하는 고급 패턴 적용
이제 여러분은 프로덕션 환경에서 확장 가능하고 유지보수가 용이한 Terraform 아키텍처를 설계하고 구현할 수 있는 실무 역량을 갖추게 되었습니다. 특히 팀 간 협업이 필요한 복잡한 인프라 환경에서 효율적인 Terraform 관리 전략을 수립하고 적용할 수 있을 것입니다.

실습에서 학습한 패턴들을 실제 업무에 적용하여 더욱 안정적이고 효율적인 인프라 관리를 실현해보시기 바랍니다.
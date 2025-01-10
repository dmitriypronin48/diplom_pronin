# diplom_pronin

### Создаем Bastion host
- Провалиемся "Все сервисы -> Compute Cloud -> Виртуальные машины -> Создать"
- В открывшемся окне выбираем следующее:
    - Образ: Ubuntu 24.04
    - Расположение: любое
    - Диски и файловые хранилища: HDD - 20 GB
    - Вычислительные ресурсы: своя конфигурация
        - Платформа: Intel Ice Lake
        - vCPU: 2
        - Гарантированная доля vCPU: 50%
        - Прерываемая: нет
    - Сетевой интерфейс №0
        - Подсеть: не меняем
        - Публичный адрес: автоматичеси
        - Группы безопасности:
            - Имя: любое читаемое 
            - Описание: Доступ из-вне только по ssh
    - Доступ:
        - Логин: любой
        - SSH-ключ: вставляем свой публичный
    - Общая информация:
        - Имя: bastion
        - Описание: любое
- Создать ВМ
- Ждем создания и проваливаемся в "Virtual Private Cloud -> Группы безопасности"
- Редактировать
- Создаем правило для входящего трафика по аналогии со скриншотом (ICMP и any на все порты потом удалим, надо временно для установки пакетов)
- Создаем правило полного доступа на исходящий трафик по аналогии со скриншотом
![Скрин 1](img/bez-1.jpg)
![Скрин 2](img/bez-2.jpg)

### Настройка Bastion/Jump host
Все дальнейшие шаги делаем от рута

Ставим пакеты:
```
apt install wget curl unzip -y
```
Ставим Terrafrom версии 1.9.8
```
wget https://hashicorp-releases.yandexcloud.net/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip && unzip terraform_1.9.8_linux_amd64.zip -d /usr/bin
```
Проверка работы терраформа terraform --version , если все ок, должен отдать версию терраформа.

Установка утилит яндекса
```
curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash 
cp yandex-cloud/bin/* /usr/bin/
```
Инициализация - yc init , команда выдаст нам ссылку , которую нужно вставить в браузере и получить токен для дальнейшей работы.
Стандартные значения, отвечаем на все вопросы в консоли и успешно выполняем инициализацию.
![Скрин 3](img/init_all.png)

Далее потребутся создать сервисный аккаунт.
в https://console.yandex.cloud/ и выполняем:

- Сверху выбераем раздел «Сервисные аккаунты»
- Создаем новый аккаунт с любым именем и ролью admin. Для этого кликаем на троеточие в правом верхнем углу → «Создать сервисный аккаунт»
- Нажимаем на созданную учётную запись
- Копируем ID себе

Подключаемся к машине bastion.
требуется скорректировать через nano ~/.terraformrc ,  вписываем:
```
provider_installation {
  network_mirror {
    url = "https://terraform-mirror.yandexcloud.net/"include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
```

Делается это для того, чтобы провайдер бралились из https://terraform-mirror.yandexcloud.net/ , чтобы тераформ не пытался скачивать провайдеры из своего репозитория.

Создаем ключ авторизации для провайдера:
```
yc iam key create \
  --service-account-id <id сервисного аккаунта, который копировали себе> \
  --folder-name default \
  --output key.json 
```

Требуется еще войти в https://console.yandex.cloud/ забрать нужные нам данные для авторизации в консоле:

- имя облака — оно начинается с cloud-. Рядом с ним появится ID, который нужно скопировать себе.
- имя каталога под названием облака — сохраняем себе ID.


Идем в консоль нашей машины bastion
По очереди выполняем команды и записываем их себе, потому что при перезагрузке ВМ настройки слетят и придется выполнять их по-новой:
```
yc config profile create <любое имя профиля> - создается один раз
yc config set service-account-key key.json - ключ которы генерился после инициализации
yc config set cloud-id <ID облака> 
yc config set folder-id <ID каталога>
    
export YC_TOKEN=$(yc iam create-token) 
export YC_CLOUD_ID=$(yc config get cloud-id)
export YC_FOLDER_ID=$(yc config get folder-id) 
```

Настраиваем провайдер. Для этого создадим новый каталог с любым именем и перейдем в него, после чего создаем файл providers.tf
```
mkdir ~/terraform_yandex && cd ~/terraform_yandex && touch providers.tf
```
В созданном файле добавляем содержимое
```
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = "ru-central1-b"
}
```
Для проверки, что нет ошибки выполним команду terraform init
![Скрин 4](img/init_success.png)


### Описание структуры
1. providers.tf - настройка провайдера, уже выполнено
2. variables.tf - тут хранятся только дефолтные значения, которые можно переписать в других файлах
3. terraform.tfvars - файлы с переменными. Они используются для перезаписи из variables.tf
4. output.tf - в нем описывается что должно отобразиться в консоли после выполнения действий
5. main.tf - что будет делать терраформ

variables.tf
```
variable "virtual_machines" {
 default = ""
}

variable "subnets" {
 default = ""
}
```

Всю структуру описываем в *.tfvars. Для этого создадим файл vms.tfvars с содержимым:
```
subnets = {
  "s-1" = {
    name = "sub-1"
    zone = "ru-central1-a"
    v4_cidr_blocks = ["192.168.20.0/24"]
  },
  "s-2" = {
    name = "sub-2"
    zone = "ru-central1-b"
    v4_cidr_blocks = ["192.168.30.0/24"]
  },
  "s-3" = {
    name = "sub-3"
    zone = "ru-central1-b"
    v4_cidr_blocks = ["192.168.40.0/24"]
  }
}

virtual_machines = {
    "vm-1" = {
      vm_name       = "site-1" # Имя ВМ
      vm_desc       = "Описание для нас. Его видно только здесь" # Описание
      vm_cpu        = 2 # Кол-во ядер процессора
      ram           = 2 # Оперативная память в ГБ
      disk          = 10 # Объем диска в ГБ
      disk_name     = "site-1-disk" # Название диска
      template      = "fd85bll745cg76f707mq" # ID образа ОС для использования
      public_ip     = false
      managed       = true
      zone          = "ru-central1-a"
      disk_type     = "network-hdd"
      core_fraction = 20
      platform_id   = "standard-v3"
      subnet        = "s-1"
    },
    "vm-2" = {
      vm_name      = "site-2" # Имя ВМ
      vm_desc      = "Описание для инженеров. Его видно только здесь"
      vm_cpu       = 2 # Кол-во ядер процессора
      ram          = 2 # Оперативная память в ГБ
      disk         = 10 # Объем диска в ГБ
      disk_name    = "site-2-disk" # Название диска
      template     = "fd85bll745cg76f707mq" # ID образа ОС для использования
      public_ip    = false
      managed      = true
      zone         = "ru-central1-b"
      disk_type    = "network-hdd"
      core_fraction = 20
      platform_id   = "standard-v3"
      subnet        = "s-2"
    },
    "vm-3" = {
      vm_name      = "elasticsearch" # Имя ВМ
      vm_desc      = "Описание для инженеров. Его видно только здесь"
      vm_cpu       = 2 # Кол-во ядер процессора
      ram          = 2 # Оперативная память в ГБ
      disk         = 20 # Объем диска в ГБ
      disk_name    = "elasticsearch4-disk" # Название диска
      template     = "fd85bll745cg76f707mq" # ID образа ОС для использования
      public_ip    = false
      managed      = true
      zone         = "ru-central1-a"
      disk_type    = "network-hdd"
      core_fraction = 100
      platform_id   = "standard-v3"
      subnet        = "s-1"
    },
    "vm-4" = {
      vm_name      = "zabbix" # Имя ВМ
      vm_desc      = "Описание для инженеров. Его видно только здесь"
      vm_cpu       = 2 # Кол-во ядер процессора
      ram          = 2 # Оперативная память в ГБ
      disk         = 20 # Объем диска в ГБ
      disk_name    = "zabbix-disk" # Название диска
      template     = "fd85bll745cg76f707mq" # ID образа ОС для использования
      public_ip    = true
      managed      = true
      zone         = "ru-central1-a"
      disk_type    = "network-hdd"
      core_fraction = 100
      platform_id   = "standard-v3"
      subnet        = "s-1"
    },
    "vm-5" = {
      vm_name      = "kibana" # Имя ВМ
      vm_desc      = "Описание для инженеров. Его видно только здесь"
      vm_cpu       = 2 # Кол-во ядер процессора
      ram          = 2 # Оперативная память в ГБ
      disk         = 20 # Объем диска в ГБ
      disk_name    = "kibana-disk" # Название диска
      template     = "fd85bll745cg76f707mq" # ID образа ОС для использования
      public_ip    = true
      managed      = true
      zone         = "ru-central1-a"
      disk_type    = "network-hdd"
      core_fraction = 100
      platform_id   = "standard-v3"
      subnet        = "s-1"
    }
}
```
Надо создать ключ пару
```
ssh-keygen -t ed25519
```
Ключи будут вот тут -->> ~/.ssh/id_ed25519.pub и тут же приватник

Создаем файл main.tf с содержимым:
```
resource "yandex_compute_disk" "boot-disk" {
  for_each = var.virtual_machines
  name     = each.value["disk_name"]
  type     = each.value["disk_type"]
  zone     = each.value["zone"]
  size     = each.value["disk"]
  image_id = each.value["template"]
}

resource "yandex_vpc_network" "network-1" {
  name = "network-1"
}

resource "yandex_vpc_subnet" "subnet" {
  for_each       = var.subnets
  name           = each.value["name"]
  zone           = each.value["zone"]
  network_id     = yandex_vpc_network.network-1.id
  v4_cidr_blocks = each.value["v4_cidr_blocks"]
}

resource "yandex_compute_instance" "virtual_machine" {
  for_each        = var.virtual_machines
  name = each.value["vm_name"]
  zone = each.value["zone"]
  allow_stopping_for_update = true

  platform_id = each.value["platform_id"]
  resources {
    cores  = each.value["vm_cpu"]
    memory = each.value["ram"]
    core_fraction = each.value["core_fraction"]
  }

  boot_disk {
    disk_id = yandex_compute_disk.boot-disk[each.key].id
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet[each.value.subnet].id
    nat       = each.value["public_ip"]
  }

  metadata = {
    ssh-keys = "dmitriy_pronin:${file("~/.ssh/id_ed25519.pub")}"
  }
}
```

Далее запускаем terraform apply и ждем как все прокатиться.
![Скрин 4](img/aply.jpg)

PS: на моменте создания виртуалок может возникнуть ошибка связанная с квотой. Для ее устранения придется делать заявку на повышения квоты на сети. делают быстро.

Заходим на бастион в клауде, выключаем и добавляем ему сетевой интерфейс в одной из созданных сетей. После чего добавляем в системе в таблицу маршрутизации маршруты
```
ip route add 192.168.30.0/24 via 192.168.40.1
ip route add 192.168.20.0/24 via 192.168.40.1
```
Далее идем настраивать балансеры.
в main.tf дописываем
```
resource "yandex_lb_target_group" "nlb-group" {
  name      = "nlb-group-1"
  region_id = "ru-central1"

  target {
    subnet_id = yandex_vpc_subnet.subnet["s-1"].id
    address   = yandex_compute_instance.virtual_machine["vm-1"].network_interface.0.ip_address
  }

  target {
    subnet_id = yandex_vpc_subnet.subnet["s-2"].id
    address   = yandex_compute_instance.virtual_machine["vm-2"].network_interface.0.ip_address
  }
}

resource "yandex_lb_network_load_balancer" "nlb" {
  name = "nlb"

  listener {
    name = "http"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.nlb-group.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}
```
Далее ставим ansible на машину bastion - apt install ansible.

## Работаем с ансибл
Создадим каталог для сохранения файлов ансибла и файлики 
mkdir ~/ansible && cd ~/ansible && touch inventory.yaml && touch playbook.yaml && touch ansible.cfg








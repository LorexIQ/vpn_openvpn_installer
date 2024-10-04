#!/bin/bash

openvpn_install() {
    apt update -y > /dev/null 2>&1 &
    pid=$!
    echo "[PID: ${pid}] Обновление пакетов..."
    wait $pid
    if [ $? -eq 0 ]; then
        echo "Обновление успешно завершено."
    else
        echo "Ошибка обновления пакетов."
        exit 1
    fi

    apt install openvpn easy-rsa -y > /dev/null 2>&1 &
    pid=$!
    echo "[PID: ${pid}] Установка OpenVPN..."
    wait $pid
    if [ $? -eq 0 ]; then
        echo "Установка OpenVPN успешно завершена."
    else
        echo "Ошибка при установке OpenVPN."
        exit 1
    fi
}

openvpn_certs_create() {
    echo "Подготовка директорий..."

    if [ ! -d "$rootVPN/easy-rsa" ]; then
      mkdir "$rootVPN/easy-rsa"
    fi

    cd "$rootVPN/easy-rsa/" || exit 1
    cp -R /usr/share/easy-rsa "$rootVPN/"

    if [ -d "$rootVPN/easy-rsa/pki" ]; then
      rm -r "$rootVPN/easy-rsa/pki"
    fi

    echo "Инициализация PKI..."
    ./easyrsa init-pki > /dev/null 2>&1

    input_server_name

    echo "Создание ключей центра сертификации..."
    {
        echo "server_name"
    } | ./easyrsa build-ca nopass > /dev/null 2>&1

    echo "Создание ключей ключей Диффи-Хафмана..."
    ./easyrsa gen-dh > /dev/null 2>&1

    echo "Создание HMAC ключа..."
    openvpn --genkey secret "$rootVPN/easy-rsa/pki/ta.key" > /dev/null 2>&1

    echo "Создание сертификата отзыва..."
    ./easyrsa gen-crl > /dev/null 2>&1

    echo "Сборка сертификата сервера..."
    ./easyrsa build-server-full server nopass > /dev/null 2>&1

    echo "Копирование сертификатов..."
    cp ./pki/ca.crt "$rootVPN/ca.crt"
    cp ./pki/dh.pem "$rootVPN/dh.pem"
    cp ./pki/crl.pem "$rootVPN/crl.pem"
    cp ./pki/ta.key "$rootVPN/ta.key"
    cp ./pki/issued/server.crt "$rootVPN/server.crt"
    cp ./pki/private/server.key "$rootVPN/server.key"

    echo "Создание сертификатов успешно завершено."
}

openvpn_create_config() {
    local address="10.8.0.0"
    local listen_port=1194

    echo "Создание файла конфигурации сервера..."
    cat << EOF > "$rootVPN/server.conf"
port $listen_port
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
crl-verify crl.pem
tls-auth ta.key 0
server $address 255.255.255.0
ifconfig-pool-persist /var/log/openvpn/ipp.txt
push "redirect-gateway ${interfacesNames[interfaceIndex]} bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
cipher AES-256-CBC
persist-key
persist-tun
status /var/log/openvpn/openvpn-status.log
verb 3
explicit-exit-notify 1
EOF
    echo "Файл конфигурации успешно создан."
}

ip_forwarding_setting() {
    echo "Настройка IP Forwarding..."
    cat << EOF > "/etc/sysctl.conf"
net.ipv4.ip_forward=1
EOF
    echo "Настройка изменена. Новое значение $(sysctl -p)"
}

get_interfaces() {
    local current_iface=""
    while IFS= read -r line; do
        if [[ $line =~ ^[0-9]+:\ ([^:]+): ]]; then
            current_iface=${BASH_REMATCH[1]}
        elif [[ $line =~ inet\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+) ]]; then
            interfacesNames+=("$current_iface")
            interfacesIps+=("${BASH_REMATCH[1]}")
        fi
    done < <(ip a)
}

print_interfaces() {
    echo "Выберите сетевой интерфейс для доступа в интернет:"
    for i in "${!interfacesNames[@]}"; do
        echo "$((i+1)). ${interfacesNames[$i]} [${interfacesIps[$i]}]"
    done
}

choose_interface() {
    while true; do
        print_interfaces
        read -p "Введите номер интерфейса: " choice

        if [[ $choice =~ ^[0-9]+$ ]] && (( choice > 0 && choice <= ${#interfacesNames[@]} )); then
            interfaceIndex=$((choice-1))
            cat << EOF > "$rootVPN/interface"
${interfacesIps[interfaceIndex]}
EOF
            echo "Выбран интерфейс: ${interfacesNames[interfaceIndex]}"
            break
        else
            echo "Ошибка: такого интерфейса нет."
        fi
    done
}

run_server() {
    echo "Создание задачи автозапуска..."
    systemctl enable openvpn@server > /dev/null 2>&1
    echo "Включение сервера OpenVPN..."
    systemctl start openvpn@server

    status=$(systemctl is-active openvpn@server)

    if [ "$status" = "active" ]; then
        echo "Статус сервера: успешно запущен"
    else
        echo "Статус сервера: ошибка запуска"
        exit 1
    fi
}

input_server_name() {
  while true; do
      read -p "Введите имя сервера: " server_name

      if [[ ${#server_name} -ge 3 && ${#server_name} -le 20 && "$server_name" =~ ^[a-zA-Z]+$ ]]; then
          break
      else
          echo "Ошибка: имя сервера должно содержать от 3 до 20 символов и состоять только из букв a-z или A-Z."
      fi
  done
}

configure_firewall() {
  sudo iptables -I FORWARD -i tun0 -o "${interfacesNames[interfaceIndex]}" -j ACCEPT
  sudo iptables -I FORWARD -i "${interfacesNames[interfaceIndex]}" -o tun0 -j ACCEPT
  sudo iptables -t nat -A POSTROUTING -o "${interfacesNames[interfaceIndex]}" -j MASQUERADE
  echo "Конфигурация брандмауэра завершена."
}

rootVPN="/etc/openvpn"

interfacesNames=()
interfacesIps=()

openvpn_install
openvpn_certs_create
get_interfaces
choose_interface
openvpn_create_config
ip_forwarding_setting
run_server
configure_firewall

echo "Сервер успешно инициализирован."

#!/bin/bash

print_peers() {
    echo "Список пользователей:"
    for i in "${!users_list[@]}"; do
        echo "$((i+1)). ${users_list[$i]}"
    done
}

list_peers() {
    for dir in /etc/openvpn/users/*; do
        if [ -d "$dir" ]; then
            users_list+=("$(basename "$dir")")
        fi
    done

    if [ ${#users_list[@]} -eq 0 ]; then
        echo "Нет зарегистрированных пользователей."
        exit 1
    fi

    print_peers
}

users_list=()

list_peers

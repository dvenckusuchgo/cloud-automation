#!/bin/bash
aws s3 sync --exclude "csoc-vpn-bucket*" --exclude "server.pem" --exclude "user_passwd.csv" s3://vpn-certs-and-files/ /etc/openvpn/easy-rsa/keys/
aws s3 cp s3://vpn-certs-and-files/user_passwd.csv /etc/openvpn/user_passwd.csv
aws s3 cp s3://vpn-certs-and-files/server.pem /etc/lighttpd/certs/server.pem

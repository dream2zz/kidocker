# /bin/bash

cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Secret
metadata:
  name: mysecret
type: Opaque
data:
  password: $(echo "p@ssw0rd" | base64)
  username: $(echo "admin" | base64)
EOF
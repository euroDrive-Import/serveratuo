#!/bin/bash
echo "=================================================================="
echo "   ORACLE CLOUD AMPERE - GITHUB ACTIONS                           "
echo "=================================================================="

COMPARTMENT_ID="ocid1.tenancy.oc1..aaaaaaaa6bc7dkfxbtrlddar2guti76vm6psalfblypjxfku5vcw4bt6dzua"
IMAGE_ID="ocid1.image.oc1.eu-frankfurt-1.aaaaaaaa33mxho6qsnmm4yu7xo3nrnvjubiimgqpsc5ycpoakz6pb4cts2ma"
SHAPE="VM.Standard.A1.Flex"
OCPUS=2
MEMORY_GB=12
SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCoHcAhXYaPANqVeF7m84n9/EiZffgtu4SO4mEVsAS1J02n+mHJfLQ0Xll2dkoiii+i3VdHd130mf4CJdYmGjZ97gm86mrRMlIFLnaCqVE/0VNBqYBL/ee14LffHyDzsL4RzLXGRpOViSFuSzr3dgisDpE9143TtUVqMH1teDYgO8JuEEzPaEnBJH2FSHNZBMXyjdz5XZGMsGyqwEaFSUDPvbZEdQM4XcOQGcrykPT4DCtG8CxthZ7lWIh/+zpx8Y1AmwFQYfdhDPXJvAqiZdl5evESCm/EvuOo6kKcuN56V5DolDXX3bE7XLU8a0yH63LVV8vt3Es1yvwwjfAnM4MP ssh-key-2026-05-31"

ADS=(
  "MiYQ:EU-FRANKFURT-1-AD-1"
  "MiYQ:EU-FRANKFURT-1-AD-2"
  "MiYQ:EU-FRANKFURT-1-AD-3"
)

echo "[+] Obteniendo IDs de Red..."
VCN_ID=$(oci network vcn list --compartment-id "$COMPARTMENT_ID" --display-name "vcn-ampere-cli" --query 'data[0].id' --raw-output 2>/dev/null)
SUBNET_ID=$(oci network subnet list --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" --display-name "subnet-ampere-cli" --query 'data[0].id' --raw-output 2>/dev/null)

if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" == "null" ]; then
  echo "❌ No se encontró la red. Por favor, asegúrate de que Cloud Shell creó la VCN y Subnet primero."
  exit 1
fi

echo "  Red lista → Subnet: $SUBNET_ID"
echo "=================================================================="

# Bucle de 20 intentos (aprox 15 minutos)
for intentos in {1..20}; do
  AD_INDEX=$(( (intentos - 1) % 3 ))
  CURRENT_AD="${ADS[$AD_INDEX]}"
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  INSTANCE_NAME="ampere-$(date '+%Y%m%d-%H%M%S')"

  echo "[$TIMESTAMP] Intento #$intentos → $CURRENT_AD"

  RESULT=$(oci compute instance launch \
    --compartment-id "$COMPARTMENT_ID" \
    --availability-domain "$CURRENT_AD" \
    --shape "$SHAPE" \
    --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORY_GB}" \
    --image-id "$IMAGE_ID" \
    --subnet-id "$SUBNET_ID" \
    --assign-public-ip true \
    --metadata "{\"ssh_authorized_keys\": \"$SSH_KEY\"}" \
    --display-name "$INSTANCE_NAME" \
    --is-pv-encryption-in-transit-enabled true \
    2>&1)

  STATUS=$?

  if [ $STATUS -eq 0 ]; then
    INSTANCE_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null || echo "Desconocido")
    echo "🎉 ¡ÉXITO! Instancia creada: $INSTANCE_ID"
    sleep 60
    PUBLIC_IP=$(oci compute instance list-vnics --instance-id "$INSTANCE_ID" --query 'data[0]."public-ip"' --raw-output 2>/dev/null)
    echo "🌐 IP Pública: $PUBLIC_IP"
    echo "SSH: ssh -i <tu-clave-privada> ubuntu@$PUBLIC_IP"
    exit 0
  fi

  if echo "$RESULT" | grep -qi "Out of capacity\|capacity\|InternalError\|500"; then
    echo "  ⚠️  Sin capacidad en $CURRENT_AD."
  elif echo "$RESULT" | grep -qi "LimitExceeded"; then
    echo "  ❌ Límite de cuenta alcanzado."
    exit 1
  elif echo "$RESULT" | grep -qi "NotAuthenticated\|Authorization"; then
    echo "  ❌ Error de autenticación."
    exit 1
  fi

  sleep 45
done

echo "Terminaron los 20 intentos de esta ronda. GitHub volverá a lanzarlo en breve."

# sally-turn-stun

> Serveur **TURN/STUN** (coturn) pour les apps SallyCards multijoueurs avec voice chat WebRTC.

[![Test TURN](https://github.com/salistar/sally-turn-stun/actions/workflows/test-turn.yml/badge.svg)](https://github.com/salistar/sally-turn-stun/actions/workflows/test-turn.yml)

URL publique production :
```
turn:turn.salistar.com:3478?transport=udp
turn:turn.salistar.com:3478?transport=tcp
stun:turn.salistar.com:3478
```

Username : `sallycards`
Password : voir [secrets-prod.md](https://github.com/salistar/sally-turn-stun/wiki/Secrets) (privé, accès admin)

---

## Sommaire

1. [Pourquoi un serveur TURN ?](#pourquoi-un-serveur-turn-)
2. [Architecture](#architecture)
3. [Déploiement Oracle Cloud Always Free](#déploiement-oracle-cloud-always-free)
4. [Configuration coturn](#configuration-coturn)
5. [Tests STUN/TURN — toutes les méthodes](#tests-stunturn--toutes-les-méthodes)
6. [Erreurs rencontrées et fixes](#erreurs-rencontrées-et-fixes)
7. [Monitoring](#monitoring)
8. [Mise à jour de la conf](#mise-à-jour-de-la-conf)

---

## Pourquoi un serveur TURN ?

Pour les apps multi-joueurs avec **voice chat** (Belote, Kdoub, Poker, Scopa, Tarot, etc.), on utilise WebRTC entre clients. Mais quand les deux clients sont derrière des **NAT symétriques** (cas fréquent : 4G, hôtels, entreprises), les paquets directs ne passent pas. Il faut un **relais** : c'est le serveur TURN.

- **STUN** : aide les clients à découvrir leur IP publique. Léger, gratuit côté trafic.
- **TURN** : relaie le trafic audio/vidéo. Coûteux en bande passante.

On utilise **coturn**, l'implémentation de référence open-source (utilisée par Jitsi, Discord, etc.).

---

## Architecture

```
┌─────────────┐     STUN binding     ┌─────────────┐
│  Belote app │ ─────────────────────│ TURN/STUN   │
│  (NAT sym.) │                      │   server    │
└─────────────┘                      │ Oracle ARM  │
       │                             └─────────────┘
       │                                    │
       └────── relay (TURN) if needed ──────┘
```

Stack technique :
- **VM** : Oracle Cloud Always Free, ARM Ampere A1 (4 OCPU + 24 GB RAM gratuit)
- **OS** : Ubuntu 22.04 LTS
- **Runtime** : Docker + docker-compose
- **Image** : `coturn/coturn:4.6` officiel
- **DNS** : `turn.salistar.com` → IP publique Oracle (A record)
- **TLS** : certificat Let's Encrypt (port 5349 turns)
- **Ports** : 3478 UDP+TCP (TURN/STUN), 5349 (TURNS), 49152-65535 UDP (relay)

---

## Déploiement Oracle Cloud Always Free

### 1. Créer la VM

1. Compte Oracle Cloud → https://cloud.oracle.com (Always Free Tier)
2. **Compute → Instances → Create instance**
3. Configuration :
   - Image : **Canonical Ubuntu 22.04**
   - Shape : **VM.Standard.A1.Flex** (4 OCPU, 24 GB RAM — gratuit à vie)
   - VCN : nouvelle VCN, subnet public
   - SSH : générer une clé ou utiliser la sienne
4. Note l'**IP publique** assignée

### 2. Ouvrir les ports dans le firewall Oracle

VCN → **Security Lists** → Default Security List → Add Ingress Rules :

| Source | Protocol | Port range |
|---|---|---|
| 0.0.0.0/0 | TCP | 3478 |
| 0.0.0.0/0 | UDP | 3478 |
| 0.0.0.0/0 | TCP | 5349 |
| 0.0.0.0/0 | UDP | 49152-65535 |
| 0.0.0.0/0 | TCP | 80 (Let's Encrypt) |
| 0.0.0.0/0 | TCP | 443 |
| 0.0.0.0/0 | TCP | 22 (SSH) |

### 3. Configurer iptables Ubuntu (ports systèmes)

Oracle ajoute des règles iptables défaut bloquantes. Il faut les overrider :

```bash
ssh ubuntu@<IP-PUBLIQUE>
sudo iptables -I INPUT -p tcp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 5349 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 49152:65535 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

### 4. Installer Docker

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo usermod -aG docker ubuntu
exit  # se reconnecter pour charger le groupe
```

### 5. Cloner ce repo

```bash
git clone https://github.com/salistar/sally-turn-stun.git
cd sally-turn-stun
```

### 6. Configurer le DNS

Provider DNS de `salistar.com` → ajouter :
```
turn.salistar.com    A     <IP-PUBLIQUE-ORACLE>
TTL                  300
```

Vérifier :
```bash
dig turn.salistar.com +short
# Doit retourner l'IP Oracle
```

### 7. Obtenir certificat TLS (Let's Encrypt)

```bash
sudo apt install -y certbot
sudo certbot certonly --standalone -d turn.salistar.com \
  --email salistarcompany@gmail.com --agree-tos --non-interactive
# Certificats générés dans /etc/letsencrypt/live/turn.salistar.com/
sudo chmod -R 755 /etc/letsencrypt
```

### 8. Lancer coturn via docker-compose

```bash
docker compose up -d
docker compose logs -f sallycards-turn
```

Logs attendus :
```
0: log file opened: stdout
0: pid file created: /var/tmp/turnserver.pid
0: Listener address requested for default address: 0.0.0.0
0: Total General servers: 5
0: IPv4. Listener address: 0.0.0.0:3478
0: SSL/TLS supported, using OpenSSL ...
```

---

## Configuration coturn

Fichier : [`docker/turnserver.conf`](docker/turnserver.conf)

```conf
listening-port=3478
tls-listening-port=5349
fingerprint
lt-cred-mech
realm=salistar.com
server-name=salistar.com

# Users (en prod : utiliser turnadmin pour gérer dynamiquement)
user=sallycards:CHANGE_ME_IN_PROD

# Certificats TLS
cert=/etc/letsencrypt/live/turn.salistar.com/fullchain.pem
pkey=/etc/letsencrypt/live/turn.salistar.com/privkey.pem

# Relay address (IP publique de la VM)
external-ip=<IP-PUBLIQUE>

# Sécurité
no-loopback-peers
no-multicast-peers
no-cli
no-tlsv1
no-tlsv1_1
cipher-list="ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20"

# Plage de ports relay
min-port=49152
max-port=65535

# Logs
log-file=stdout
verbose
```

`docker-compose.yml` :

```yaml
services:
  sallycards-turn:
    image: coturn/coturn:4.6
    container_name: sallycards-turn
    restart: unless-stopped
    network_mode: host    # important pour les ports relay UDP
    volumes:
      - ./docker/turnserver.conf:/etc/coturn/turnserver.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
```

---

## Tests STUN/TURN — toutes les méthodes

### Méthode 1 — Trickle ICE (le + visuel)

1. Aller sur https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/
2. Click **Remove server**, puis **Add server** :
   - URI : `turn:turn.salistar.com:3478`
   - Username : `sallycards`
   - Password : `<password>`
3. Click **Add Server** puis **Gather candidates**
4. Doit afficher des candidats `srflx` (STUN) ET `relay` (TURN)

✅ **Si vous voyez `relay 192.x.x.x:..._relay`** → TURN fonctionne.
❌ Si vous voyez seulement `srflx` → TURN ne relaie pas (firewall/port).

### Méthode 2 — turnutils_uclient (le + complet)

```bash
# Installer (Ubuntu / Mac)
sudo apt install -y coturn   # juste pour les outils
# ou : brew install coturn

# STUN test
turnutils_stunclient -p 3478 turn.salistar.com
# Output attendu : "Mapped address ..." avec l'IP publique

# TURN test (UDP)
turnutils_uclient -y -t -u sallycards -w '<password>' \
  -e turn.salistar.com -W '<password>' turn.salistar.com
# "TLS using ..." → succès

# TURN test (TCP)
turnutils_uclient -t -u sallycards -w '<password>' turn.salistar.com
```

### Méthode 3 — Script bash inclus

```bash
./scripts/test-turn.sh turn.salistar.com sallycards <password>
```

Le script :
1. Test DNS
2. Test STUN binding
3. Test TURN allocate
4. Test TURN relay (envoie + reçoit un paquet)
5. Affiche un récapitulatif

### Méthode 4 — Depuis l'app SallyCards (production-like)

Lancer une partie en ligne dans Belote/Poker/Kdoub. Dans logcat, chercher :
```
[WebRTC] ICE candidate: typ relay raddr ... rport ...
[WebRTC] Connection state: connected
```

Si vous voyez `typ relay` dans les candidats → TURN est utilisé pour le voice.

### Méthode 5 — netstat / ss côté serveur

```bash
ssh ubuntu@<IP>
sudo ss -lntu | grep -E '3478|5349'
# Doit afficher :
# udp UNCONN 0 0 0.0.0.0:3478
# tcp LISTEN 0 511 0.0.0.0:3478
# tcp LISTEN 0 511 0.0.0.0:5349

# Trafic actif
sudo ss -anu | grep 3478 | head -20
```

---

## Erreurs rencontrées et fixes

| Erreur | Cause | Fix |
|---|---|---|
| `iptables: Operation not permitted` | Pas root | `sudo` devant la commande |
| `bind: Address already in use` (3478) | Un autre coturn tourne | `docker compose down` ; `sudo lsof -i :3478` ; tuer |
| `STUN binding ne renvoie rien` | Port UDP 3478 non ouvert dans VCN Oracle | Ajouter ingress rule UDP 3478 |
| `TURN allocate échoue avec "401 Unauthorized"` | Mauvais user/password ou realm | Vérifier `lt-cred-mech` + `realm=` + `user=` dans turnserver.conf |
| `Pas de candidat 'relay' dans Trickle ICE` | Plage 49152-65535 UDP fermée | Ouvrir cette plage côté Oracle VCN |
| `Certificate verification failed` (TURNS port 5349) | Cert expiré ou bad chain | `certbot renew --force-renewal` + redémarrer coturn |
| `coturn ignore turnserver.conf` | Mauvais path mount | `docker compose down ; up -d` ; vérifier `volumes` |
| `external-ip mal configuré` | IP changée après reboot | Réserver l'IP publique en "Reserved" dans Oracle VCN |
| `Connexion refusée depuis l'app mobile` | Mobile sur un réseau qui bloque UDP | Activer aussi TCP transport (`transport=tcp` dans iceServers) |
| `ICE failed` côté Belote | TURN OK mais signaling Socket.IO pas synchronisé | Vérifier que les deux clients utilisent le MÊME serveur TURN |

---

## Monitoring

### Logs en temps réel

```bash
docker compose logs -f sallycards-turn | grep -v "DEBUG"

# Ou : filtrer les sessions actives
docker compose logs sallycards-turn | grep "session.*allocated"
```

### Stats (Prometheus exporter)

Ajouter un sidecar `coturn_exporter` dans `docker-compose.yml` (optionnel) :

```yaml
  turn-exporter:
    image: spotsoftware/coturn-prometheus-exporter
    network_mode: host
    environment:
      COTURN_HOST: localhost
      COTURN_PORT: 3478
    ports:
      - "9641:9641"
```

Métriques disponibles : `coturn_sessions_total`, `coturn_traffic_bytes`, etc.

### Alerte Slack si serveur down

Cron simple :
```bash
*/5 * * * * curl -s --max-time 5 stun:turn.salistar.com:3478 || \
  curl -X POST <slack-webhook> -d '{"text":"TURN server DOWN"}'
```

---

## Mise à jour de la conf

```bash
ssh ubuntu@<IP>
cd sally-turn-stun
git pull origin main
docker compose down
docker compose up -d
```

CI : à chaque push sur `main`, le workflow [`test-turn.yml`](.github/workflows/test-turn.yml) vérifie automatiquement que `turn.salistar.com` répond (STUN + TURN allocate). Si KO → notification Slack.

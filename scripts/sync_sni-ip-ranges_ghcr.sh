#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Sync sni-ip-ranges ==> GHCR
## Self: https://raw.githubusercontent.com/pkgforge-security/domains/refs/heads/main/scripts/sync_sni-ip-ranges_ghcr.sh
#-------------------------------------------------------#


#-------------------------------------------------------#
##Sanity
if [ -z "${GHCR_TOKEN+x}" ] || [ -z "${GHCR_TOKEN##*[[:space:]]}" ]; then
  echo -e "\n[-] FATAL: Failed to Find GHCR_TOKEN (\${GHCR_TOKEN}\n"
 exit 1
fi 
if ! command -v oras &> /dev/null; then
  echo -e "[-] Failed to find oras\n"
 exit 1
else
  oras login --username "Azathothas" --password "${GHCR_TOKEN}" "ghcr.io"
fi
##ENV
export TZ="UTC"
SYSTMP="$(dirname $(mktemp -u))" && export SYSTMP="${SYSTMP}"
TMPDIR="$(mktemp -d)" && export TMPDIR="${TMPDIR}" ; echo -e "\n[+] Using TEMP: ${TMPDIR}\n"
rm -rf "${SYSTMP}/DATA" 2>/dev/null ; mkdir -p "${SYSTMP}/DATA"
if [[ -z "${USER_AGENT}" ]]; then
 USER_AGENT="$(curl -qfsSL 'https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Misc/User-Agents/ua_firefox_macos_latest.txt')"
fi
##Repo
 ORAS_LOCAL="$(mktemp -d)"
 GHCRPKG_URL="ghcr.io/pkgforge-security/domains/sni-ip-ranges"
 PKG_WEBPAGE="$(echo "https://github.com/pkgforge-security/domains" | sed 's|^/*||; s|/*$||' | tr -d '[:space:]')"
 export GHCRPKG_URL ORAS_LOCAL PKG_WEBPAGE
#-------------------------------------------------------#

#-------------------------------------------------------#
##Func
sync_to_ghcr()
{
 if [[ -d "${ORAS_LOCAL}/DATA/sni-ip-ranges" ]] && \
  [[ "$(du -s "${ORAS_LOCAL}/DATA/sni-ip-ranges" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 100000 ]]; then
  pushd "${ORAS_LOCAL}" &>/dev/null &&\
   unset GHCRPKG_TAG
   GHCRPKG_TAG="$(echo "${I_D}-${MODTIME}" | sed 's/[^a-zA-Z0-9._-]/_/g; s/_*$//')"
   export GHCRPKG_TAG
   #Check Tag
    if ! oras manifest fetch "${GHCRPKG_URL}:${GHCRPKG_TAG}" |\
      jq -r '.annotations["org.opencontainers.image.created"]' | tr -d '[:space:]' |\
       grep -qiE '[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
        oras push --debug --config "/dev/null:application/vnd.oci.empty.v1+json" "${GHCRPKG_URL}:${GHCRPKG_TAG}"
        sleep 2
    fi
   #Construct Upload CMD
     ghcr_push_cmd()
     {
      for i in {1..10}; do
        pushd "${ORAS_LOCAL}" &>/dev/null
        if [ -z "${PKG_DATE+x}" ] || [ -z "${PKG_DATE##*[[:space:]]}" ]; then
           PKG_DATETMP="$(date --utc +%Y-%m-%dT%H:%M:%S)Z"
           PKG_DATE="$(echo "${PKG_DATETMP}" | sed 's/ZZ\+/Z/Ig' | tr -d '[:space:]')"
        fi
        #unset ghcr_push ; ghcr_push=(oras push --concurrency "10" --disable-path-validation)
        unset ghcr_push ; ghcr_push=(oras push --disable-path-validation)
        ghcr_push+=(--config "/dev/null:application/vnd.oci.empty.v1+json")
        ghcr_push+=(--annotation "com.github.package.type=container")
        ghcr_push+=(--annotation "dev.pkgforge-security.domains.upload_date=${PKG_DATE}")
        ghcr_push+=(--annotation "org.opencontainers.image.authors=https://docs.pkgforge.dev/contact/chat")
        ghcr_push+=(--annotation "org.opencontainers.image.created=${PKG_DATE}")
        ghcr_push+=(--annotation "org.opencontainers.image.description=sni-ip-ranges-data-${I_D}")
        ghcr_push+=(--annotation "org.opencontainers.image.documentation=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.licenses=blessing")
        ghcr_push+=(--annotation "org.opencontainers.image.ref.name=${I_D}")
        ghcr_push+=(--annotation "org.opencontainers.image.revision=${I_D}")
        ghcr_push+=(--annotation "org.opencontainers.image.source=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.title=sni-ip-ranges-${I_D}")
        ghcr_push+=(--annotation "org.opencontainers.image.url=${SRC_URL}")
        ghcr_push+=(--annotation "org.opencontainers.image.vendor=pkgforge-security")
        ghcr_push+=(--annotation "org.opencontainers.image.version=${I_D}")
        ghcr_push+=("${GHCRPKG_URL}:${GHCRPKG_TAG},${I_D}")
        pushd "${ORAS_LOCAL}/DATA/sni-ip-ranges" &>/dev/null
        oras_files=() ; mapfile -t oras_files < <(find "." -maxdepth 1 -type f -not -path "*/\.*" -print 2>/dev/null)
         for o_f in "${oras_files[@]}"; do
           [[ -f "${o_f}" && -s "${o_f}" ]] && ghcr_push+=("${o_f}")
         done
        "${ghcr_push[@]}" ; sleep 5
       #Check
        if [[ "$(oras manifest fetch "${GHCRPKG_URL}:${GHCRPKG_TAG}" | jq -r '.annotations["dev.pkgforge-security.domains.upload_date"]' | tr -d '[:space:]')" == "${PKG_DATE}" ]]; then
          echo -e "\n[+] Registry --> https://${GHCRPKG_URL}"
          cp -rfv "${ORAS_LOCAL}/DATA/sni-ip-ranges/." "${SYSTMP}/DATA"
          pushd "${TMPDIR}" &>/dev/null ; return
        else
          echo -e "\n[-] Failed to Push Artifact to ${GHCRPKG_URL}:${GHCRPKG_TAG} (Retrying ${i}/10)\n"
        fi
        sleep "$(shuf -i 500-4500 -n 1)e-3"
      done
     }
     export -f ghcr_push_cmd
    #First Set of tries
     ghcr_push_cmd
    #Check if Failed  
     if [[ "$(oras manifest fetch "${GHCRPKG_URL}:${GHCRPKG_TAG}" | jq -r '.annotations["dev.pkgforge-security.domains.upload_date"]' | tr -d '[:space:]')" != "${PKG_DATE}" ]]; then
       echo -e "\n[✗] Failed to Push Artifact to ${GHCRPKG_URL}:${GHCRPKG_TAG}\n"
       #Second set of Tries
        echo -e "\n[-] Retrying ...\n"
        ghcr_push_cmd
         if [[ "$(oras manifest fetch "${GHCRPKG_URL}:${GHCRPKG_TAG}" | jq -r '.annotations["dev.pkgforge-security.domains.upload_date"]' | tr -d '[:space:]')" != "${PKG_DATE}" ]]; then
           oras manifest fetch "${GHCRPKG_URL}:${GHCRPKG_TAG}" | jq .
           echo -e "\n[✗] Failed to Push Artifact to ${GHCRPKG_URL}:${GHCRPKG_TAG}\n"
           pushd "${TMPDIR}" &>/dev/null ; return
         fi
     fi
  du -sh "${ORAS_LOCAL}/DATA/sni-ip-ranges" && realpath "${ORAS_LOCAL}/DATA/sni-ip-ranges"
 fi
}
export -f sync_to_ghcr
#-------------------------------------------------------#


#-------------------------------------------------------#
##SRC//DEST
pushd "${TMPDIR}" &>/dev/null && export DOMAIN_SRC="sni-ip-ranges"
#https://kaeferjaeger.gay/?dir=sni-ip-ranges
I_SRCS=(amazon digitalocean google microsoft oracle)
echo -e "\n[+] Data: ${I_SRCS[*]}\n"
if [[ -n "${I_SRCS[*]}" && "${#I_SRCS[@]}" -ge 1 ]]; then
  #Check
   unset I_D SRC_URL_STATUS SRC_URL_TMP
   SRC_URL_STATUS="$(curl -X "HEAD" -qfksSL "https://kaeferjaeger.gay/?dir=sni-ip-ranges" -I | sed -n 's/^[[:space:]]*HTTP\/[0-9.]*[[:space:]]\+\([0-9]\+\).*/\1/p' | tail -n1 | tr -d '[:space:]')"
   if echo "${SRC_URL_STATUS}" | grep -qiv '200$'; then
      SRC_URL_STATUS="$(curl -A "${USER_AGENT}" -X "HEAD" -qfksSL "https://kaeferjaeger.gay/?dir=sni-ip-ranges" -I | sed -n 's/^[[:space:]]*HTTP\/[0-9.]*[[:space:]]\+\([0-9]\+\).*/\1/p' | tail -n1 | tr -d '[:space:]')"
      echo -e "\n[-] FATAL: Server seems to be Offline\n"
      curl -A "${USER_AGENT}" -w "(SERVER) <== %{url}\n" -X "HEAD" -qfksSL "https://kaeferjaeger.gay/?dir=sni-ip-ranges" -I ; echo -e "\n"
     exit 1
   elif [[ "${SRC_URL_STATUS}" == "200" ]]; then
     SRC_URL_TMP="https://kaeferjaeger.gay/?dir=sni-ip-ranges"
   fi
   echo -e "\n[+] Server ==> ${SRC_URL_TMP}"
  #Download
   for I_D in "${I_SRCS[@]}"; do 
    echo -e "\n[+] Processing ${I_D}"
     #Set
      unset INPUT_TMP MODTIME MODTIME_TEMP NO_GZ SRC_URL
      INPUT_TMP="$(echo "${I_D}" | tr -d '[:space:]')"
      SRC_URL="https://kaeferjaeger.gay/sni-ip-ranges/${I_D}/ipv4_merged_sni.txt"
     #Get
      for i in {1..2}; do
        curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -kfSL "${SRC_URL}" --retry 3 --retry-all-errors -o "${TMPDIR}/${I_D}.txt"
        if [[ -s "${TMPDIR}/${I_D}.txt" && $(stat -c%s "${TMPDIR}/${I_D}.txt") -gt 10000 ]]; then
           du -sh "${TMPDIR}/${I_D}.txt"
           #Get modtime
            MODTIME="$(curl -A "${USER_AGENT}" -qfksSL "http://kaeferjaeger.gay/?dir=sni-ip-ranges/${I_D}" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}' | sed -E 's/[[:space:]]+/_/; s/:/-/g' | tr -d '[:space:]')"
            if [[ -z "${MODTIME+x}" ]] || [[ "$(printf '%s' "${MODTIME}" | wc -c)" -lt 10 ]]; then
               MODTIME_TEMP="$(date --utc +%Y-%m-%d_T%H-%M-%S)"
               MODTIME="$(echo "${MODTIME_TEMP}" | sed 's/ZZ\+/Z/Ig' | tr -d '[:space:]')"
            fi
            export MODTIME
           #Copy
             rm -rf "${ORAS_LOCAL}/DATA/sni-ip-ranges" 2>/dev/null
             mkdir -p "${ORAS_LOCAL}/DATA/sni-ip-ranges"
             cp -fv "${TMPDIR}/${I_D}.txt" "${ORAS_LOCAL}/DATA/sni-ip-ranges/${I_D}.txt"
           #Upload
             sync_to_ghcr
           #Break
             pushd "${TMPDIR}" &>/dev/null ; break
        else
           echo "Retrying... ${i}/2"
          sleep 2
        fi
      done
   done
else
  echo -e "\n[-] FATAL: Failed to Set Sources\n"
  echo -e "[+] Sources : ${I_SRCS[*]}"
 exit 1
fi
#-------------------------------------------------------#
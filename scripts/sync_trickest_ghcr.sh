#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Sync trickest ==> GHCR
## Self: https://raw.githubusercontent.com/pkgforge-security/domains/refs/heads/main/scripts/sync_trickest_ghcr.sh
#-------------------------------------------------------#


#-------------------------------------------------------#
##Sanity
if [ -z "${GHCR_TOKEN+x}" ] || [ -z "${GHCR_TOKEN##*[[:space:]]}" ]; then
  echo -e "\n[-] FATAL: Failed to Find GHCR_TOKEN (\${GHCR_TOKEN}\n"
 exit 1
fi
if ! command -v dasel &> /dev/null; then
  echo -e "[-] Failed to find dasel\n"
 exit 1 
fi
if ! command -v oras &> /dev/null; then
  echo -e "[-] Failed to find oras\n"
 exit 1
else
  oras login --username "Azathothas" --password "${GHCR_TOKEN}" "ghcr.io"
fi
if ! command -v qsv &> /dev/null; then
  echo -e "[-] Failed to find qsv\n"
 exit 1
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
 GHCRPKG_URL="ghcr.io/pkgforge-security/domains/trickest"
 PKG_WEBPAGE="$(echo "https://github.com/pkgforge-security/domains" | sed 's|^/*||; s|/*$||' | tr -d '[:space:]')"
 export GHCRPKG_URL ORAS_LOCAL PKG_WEBPAGE
#-------------------------------------------------------#

#-------------------------------------------------------#
##Func
sync_to_ghcr()
{
 if [[ -d "${ORAS_LOCAL}/DATA/trickest" ]] && \
  [[ "$(du -s "${ORAS_LOCAL}/DATA/trickest" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 1000 ]]; then
  pushd "${ORAS_LOCAL}" &>/dev/null &&\
   unset GHCRPKG_TAG
   GHCRPKG_TAG="$(echo "${COMMIT_HASH}" | sed 's/[^a-zA-Z0-9._-]/_/g; s/_*$//')"
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
        ghcr_push+=(--annotation "org.opencontainers.image.description=trickest-data-${UPDATED_AT}")
        ghcr_push+=(--annotation "org.opencontainers.image.documentation=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.licenses=blessing")
        ghcr_push+=(--annotation "org.opencontainers.image.ref.name=${UPDATED_AT}")
        ghcr_push+=(--annotation "org.opencontainers.image.revision=${UPDATED_AT}")
        ghcr_push+=(--annotation "org.opencontainers.image.source=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.title=trickest-${UPDATED_AT}")
        ghcr_push+=(--annotation "org.opencontainers.image.url=${SRC_URL}")
        ghcr_push+=(--annotation "org.opencontainers.image.vendor=pkgforge-security")
        ghcr_push+=(--annotation "org.opencontainers.image.version=${UPDATED_AT}")
        ghcr_push+=("${GHCRPKG_URL}:${GHCRPKG_TAG},trickest")
        pushd "${ORAS_LOCAL}/DATA/trickest" &>/dev/null
        oras_files=() ; mapfile -t oras_files < <(find "." -maxdepth 1 -type f -not -path "*/\.*" -print 2>/dev/null)
         for o_f in "${oras_files[@]}"; do
           [[ -f "${o_f}" && -s "${o_f}" ]] && ghcr_push+=("${o_f}")
         done
        "${ghcr_push[@]}" ; sleep 5
       #Check
        if [[ "$(oras manifest fetch "${GHCRPKG_URL}:${GHCRPKG_TAG}" | jq -r '.annotations["dev.pkgforge-security.domains.upload_date"]' | tr -d '[:space:]')" == "${PKG_DATE}" ]]; then
          echo -e "\n[+] Registry --> https://${GHCRPKG_URL}"
          #mv -fv "${ORAS_LOCAL}/DATA/trickest/." "${SYSTMP}/DATA"
          echo "ARTIFACTS_PATH=${ORAS_LOCAL}/DATA/trickest" >> "${GITHUB_ENV}" 2>/dev/null
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
  du -sh "${ORAS_LOCAL}/DATA/trickest" && realpath "${ORAS_LOCAL}/DATA/trickest"
 fi
}
export -f sync_to_ghcr
#-------------------------------------------------------#


#-------------------------------------------------------#
##SRC//DEST
#https://github.com/trickest/cloud
unset COMMIT_DATE COMMIT_HASH SRC_REPO UPDATED_AT UPSTREAM_HASH
pushd "$(mktemp -d)" &>/dev/null &&\
 git clone --depth="1" --filter="blob:none" --single-branch --quiet "https://github.com/trickest/cloud" "./TEMPREPO" &>/dev/null &&\
 cd "./TEMPREPO" && SRC_REPO="$(realpath .)"
 COMMIT_HASH="$(git --git-dir="${SRC_REPO}/.git" --no-pager log -1 --pretty=format:'HEAD-%h-%cd' --date=format:'%y%m%dT%H%M%S' | tr -d '[:space:]')"
 COMMIT_DATE="$(git --git-dir="${SRC_REPO}/.git" --no-pager log -1 --pretty=format:'%cd' --date=format:'%y%m%dT%H%M%S' | tr -d '[:space:]')"
 UPDATED_AT="$(git --git-dir="${SRC_REPO}/.git" --no-pager log -1 --date=format-local:'%Y-%m-%d_%H-%M-%S' --format='%cd' | tr -d '[:space:]')"
 UPSTREAM_HASH="$(oras repo tags "${GHCRPKG_URL}" 2>/dev/null | awk -F'-' '{print $NF}' | sort --version-sort --unique | tail -n 1 | tr -d '[:space:]')"
#Sanity Check 
 if [[ "$(echo "${COMMIT_HASH##*-}" | tr -d '[:space:]')" == "${UPSTREAM_HASH}" ]]; then
   if [[ "${FORCE_PUSH}" != "YES" ]]; then
      echo -e "\n[+] Upstream already has Latest Commit"
      echo -e "ReRun: FORCE_PUSH=\"YES\" to force Sync\n"
    exit 0
   fi
 fi
 export COMMIT_DATE COMMIT_HASH SRC_REPO UPDATED_AT
#-------------------------------------------------------#

#-------------------------------------------------------# 
#Main 
pushd "${TMPDIR}" &>/dev/null && export DOMAIN_SRC="trickest"
if [[ -d "${SRC_REPO}" ]] && [[ "$(du -s "${SRC_REPO}" | cut -f1 | tr -d '[:space:]')" -gt 1000 ]]; then
  #Generate
   unset SRC_URL_STATUS SRC_URL_TMP T_INPUT
   rm -rf "${ORAS_LOCAL}/DATA/trickest" "${TMPDIR}/DATA" 2>/dev/null
   mkdir -p "${ORAS_LOCAL}/DATA/trickest" "${TMPDIR}/DATA"
   echo -e "\n[+] Converting CSV ==> JSON (Dasel) ...\n"
   find "${SRC_REPO}" -type f -not -path "*/\.*" -iname '*.csv' -exec bash -c 'cat "$1" 2>/dev/null' _ "{}" \; > "${ORAS_LOCAL}/DATA/trickest/cloud.csv"
   find "${SRC_REPO}" -type f -not -path "*/\.*" -iname '*.csv' -exec bash -c 'dasel --file "$1" --read csv --write json > "${TMPDIR}/DATA/$(basename "${1%.csv}.json")"' _ "{}" \;
  #Parse
   rm -rf "${TMPDIR}/cloud.txt"  2>/dev/null
   readarray -t T_INPUT < <(find "${TMPDIR}/DATA" -type f -iname "*.json" -print | sort -u)
   if [[ -n "${T_INPUT[*]}" && "${#T_INPUT[@]}" -ge 10 ]]; then
     echo -e "\n[+] Total JSON: ${#T_INPUT[@]}\n"
     echo -e "[+] Checking JSON ...\n"
     find "${TMPDIR}/DATA" -type f -iname "*.json" -exec bash -c 'jq empty "{}" 2>/dev/null && cat "{}"' \; | jq -c '[.[]?] | .[]' > "${TMPDIR}/DATA/cloud.json.tmp.raw"
     echo -e "[+] Merging JSON ...\n"
     {
       echo "["
       jq -c '.' "${TMPDIR}/DATA/cloud.json.tmp.raw" 2>/dev/null | sed 's/$/,/'
       echo "]" | sed '$s/,$//'
     } > "${TMPDIR}/DATA/cloud.json.tmp"
     sed -E ':a; s/,\s*([}\]])/\1/g; s/([\[{])\s*,/\1/g; ta' -i "${TMPDIR}/DATA/cloud.json.tmp"
     sed 'N;$s/},\n\]/}\n]/;P;D' -i "${TMPDIR}/DATA/cloud.json.tmp"
    #Proces
     ##Expensive
     mv -fv "${TMPDIR}/DATA/cloud.json.tmp" "${ORAS_LOCAL}/DATA/trickest/cloud.json"
     mv -fv "${TMPDIR}/DATA/cloud.json.tmp.raw" "${ORAS_LOCAL}/DATA/trickest/cloud.jsonl"
    #Loop
     echo -e "\n[+] Generating TXT ...\n"
     for ((i = 0; i < "${#T_INPUT[@]}"; i += 10)); do
       end="$((i + 9))"
       for ((j = i; j <= end && j < "${#T_INPUT[@]}"; j++)); do
         jq -r '.[] | "\(.["IP Address"]) --> [CN: \(.["Common Name"] // "N/A") || SAN: \(.["Subject Alternative DNS Name"] // "N/A") || SAN_IP: \(.["Subject Alternative IP address"] // "N/A") || ORG: \(.["Organization"] // "N/A") || CTRY: \(.["Country"] // "N/A")]"' "${T_INPUT[j]}"
       done
     done > "${TMPDIR}/DATA/cloud.txt"
    #Filter
     sed '/^[[:space:]]*[0-9]/!d' -i "${TMPDIR}/DATA/cloud.txt"
    #Sort
     sort --version-sort --unique "${TMPDIR}/DATA/cloud.txt" --output "${ORAS_LOCAL}/DATA/trickest/cloud.txt"
    #Archive
     if [[ -s "${ORAS_LOCAL}/DATA/trickest/cloud.txt" && $(stat -c%s "${ORAS_LOCAL}/DATA/trickest/cloud.txt") -gt 1000000 ]]; then
        cp -fv "${ORAS_LOCAL}/DATA/trickest/cloud.txt" "${ORAS_LOCAL}/DATA/trickest/cloud-${COMMIT_DATE}.txt"
     else
        echo -e "\n[X] FATAL: Failed to Parse Data\n"
        du -sh "${ORAS_LOCAL}/DATA/trickest/cloud.txt"
       exit 1
     fi
     if [[ -s "${ORAS_LOCAL}/DATA/trickest/cloud.csv" && $(stat -c%s "${ORAS_LOCAL}/DATA/trickest/cloud.csv") -gt 1000000 ]]; then
       cp -fv "${ORAS_LOCAL}/DATA/trickest/cloud.csv" "${ORAS_LOCAL}/DATA/trickest/cloud-${COMMIT_DATE}.csv"
       qsv to sqlite "${ORAS_LOCAL}/DATA/trickest/cloud.db" "${ORAS_LOCAL}/DATA/trickest/cloud.csv"
       cp -fv "${ORAS_LOCAL}/DATA/trickest/cloud.db" "${ORAS_LOCAL}/DATA/trickest/cloud-${COMMIT_DATE}.db"
     else
        echo -e "\n[X] FATAL: Failed to Parse CSV Data\n"
        du -sh "${ORAS_LOCAL}/DATA/trickest/cloud.csv"
     fi
     if [[ -s "${ORAS_LOCAL}/DATA/trickest/cloud.json" && $(stat -c%s "${ORAS_LOCAL}/DATA/trickest/cloud.json") -gt 1000000 ]]; then
       cp -fv "${ORAS_LOCAL}/DATA/trickest/cloud.json" "${ORAS_LOCAL}/DATA/trickest/cloud-${COMMIT_DATE}.json"
       cp -fv "${ORAS_LOCAL}/DATA/trickest/cloud.jsonl" "${ORAS_LOCAL}/DATA/trickest/cloud-${COMMIT_DATE}.jsonl"
     else
        echo -e "\n[X] FATAL: Failed to Parse JSON Data\n"
        du -sh "${ORAS_LOCAL}/DATA/trickest/cloud.json"
     fi
    #Sync
     echo "${COMMIT_HASH}" | tr -d '[:space:]' > "${ORAS_LOCAL}/DATA/trickest/hash.txt"
     sync_to_ghcr
    #Break
     pushd "${TMPDIR}" &>/dev/null
   else
      echo -e "\n[-] FATAL: Failed to get Needed Files\n"
      echo -e "[+] Files : ${T_INPUT[*]}"
     exit 1
   fi
else
  echo -e "\n[X] FATAL: Failed to clone Trickest Repo\n"
 exit 1
fi
#-------------------------------------------------------#
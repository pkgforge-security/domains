#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Sync Certstream ==> GHCR
## Self: https://raw.githubusercontent.com/pkgforge-security/domains/refs/heads/main/scripts/sync_certstream_ghcr.sh
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
 GHCRPKG_URL="ghcr.io/pkgforge-security/domains/certstream"
 PKG_WEBPAGE="$(echo "https://github.com/pkgforge-security/domains" | sed 's|^/*||; s|/*$||' | tr -d '[:space:]')"
 export GHCRPKG_URL ORAS_LOCAL PKG_WEBPAGE
#-------------------------------------------------------#

#-------------------------------------------------------#
##Func
sync_to_ghcr()
{
 if [[ -d "${ORAS_LOCAL}/DATA/certstream" ]] && \
  [[ "$(du -s "${ORAS_LOCAL}/DATA/certstream" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 100000 ]]; then
  pushd "${ORAS_LOCAL}" &>/dev/null &&\
   export GHCRPKG_TAG="${I_D}"
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
        ghcr_push+=(--annotation "org.opencontainers.image.description=certstream-data-${I_D}")
        ghcr_push+=(--annotation "org.opencontainers.image.documentation=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.licenses=blessing")
        ghcr_push+=(--annotation "org.opencontainers.image.ref.name=${I_D}")
        ghcr_push+=(--annotation "org.opencontainers.image.revision=${I_D}")
        ghcr_push+=(--annotation "org.opencontainers.image.source=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.title=certstream-${I_D}")
        ghcr_push+=(--annotation "org.opencontainers.image.url=${SRC_URL}")
        ghcr_push+=(--annotation "org.opencontainers.image.vendor=pkgforge-security")
        ghcr_push+=(--annotation "org.opencontainers.image.version=${I_D}")
        ghcr_push+=("${GHCRPKG_URL}:${GHCRPKG_TAG}")
        pushd "${ORAS_LOCAL}/DATA/certstream" &>/dev/null
        oras_files=() ; mapfile -t oras_files < <(find "." -maxdepth 1 -type f -not -path "*/\.*" -print 2>/dev/null)
         for o_f in "${oras_files[@]}"; do
           [[ -f "${o_f}" && -s "${o_f}" ]] && ghcr_push+=("${o_f}")
         done
        "${ghcr_push[@]}" ; sleep 5
       #Check
        if [[ "$(oras manifest fetch "${GHCRPKG_URL}:${GHCRPKG_TAG}" | jq -r '.annotations["dev.pkgforge-security.domains.upload_date"]' | tr -d '[:space:]')" == "${PKG_DATE}" ]]; then
          echo -e "\n[+] Registry --> https://${GHCRPKG_URL}"
          echo "MERGE_DATA=YES" >> "${GITHUB_ENV}" 2>/dev/null
          cp -rfv "${ORAS_LOCAL}/DATA/certstream/." "${SYSTMP}/DATA"
          echo "ARTIFACTS_PATH=${ORAS_LOCAL}/DATA/certstream" >> "${GITHUB_ENV}" 2>/dev/null
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
  du -sh "${ORAS_LOCAL}/DATA/certstream" && realpath "${ORAS_LOCAL}/DATA/certstream"
 fi
}
export -f sync_to_ghcr
#-------------------------------------------------------#

#-------------------------------------------------------#
##SRC//DEST
pushd "${TMPDIR}" &>/dev/null && export DOMAIN_SRC="certstream"
#CS data for the current day is available tomorrow @ 00:15 UTC
#mapfile -t "I_DATES" < <(for i in $(seq 0 $((10#$(date --utc +%d) - 1))); do date --utc -d "-${i} days" +%Y-%m-%d; done)
I_DATES_TMP=() ; mapfile -t "I_DATES_TMP" < <(for i in $(seq 1 $((10#$(date --utc +%d) - 0))); do date --utc -d "-${i} days" +%Y-%m-%d; done | sort --version-sort --unique)
GHCR_EXISTS=() ; mapfile -t "GHCR_EXISTS" < <(oras repo tags "${GHCRPKG_URL}" 2>/dev/null | sort --version-sort --unique | sed 'N;$!P;$!D;$d' | sort -u)
I_DATES=() ; mapfile -t I_DATES < <(printf "%s\n" "${I_DATES_TMP[@]}" | grep -Fxv -f <(printf "%s\n" "${GHCR_EXISTS[@]}" | grep -oP '^\d{4}-\d{2}-\d{2}'))
echo -e "\n[+] Data: ${I_DATES[*]}\n"
if [[ -n "${I_DATES[*]}" && "${#I_DATES[@]}" -ge 1 ]]; then
  #Check
   unset I_D PKG_DATE PKG_DATETMP SRC_URL_STATUS SRC_URL_TMP
   SRC_URL_STATUS="$(curl -X "HEAD" -qfsSL "https://cs1.ip.thc.org" -I | sed -n 's/^[[:space:]]*HTTP\/[0-9.]*[[:space:]]\+\([0-9]\+\).*/\1/p' | tail -n1 | tr -d '[:space:]')"
   if echo "${SRC_URL_STATUS}" | grep -qiv '200$'; then
     SRC_URL_STATUS="$(curl -X "HEAD" -qfsSL "https://cs2.ip.thc.org" -I | sed -n 's/^[[:space:]]*HTTP\/[0-9.]*[[:space:]]\+\([0-9]\+\).*/\1/p' | tail -n1 | tr -d '[:space:]')"
     if [[ "${SRC_URL_STATUS}" == "200" ]]; then
        SRC_URL_TMP="https://cs2.ip.thc.org"
     else
        echo -e "\n[-] FATAL: Server seems to be Offline\n"
        curl -w "(SERVER) <== %{url}\n" -X "HEAD" -qfsSL "https://cs1.ip.thc.org" -I ; echo -e "\n"
        curl -w "(SERVER) <== %{url}\n" -X "HEAD" -qfsSL "https://cs2.ip.thc.org" -I ; echo -e "\n"
       exit 1
     fi
   elif [[ "${SRC_URL_STATUS}" == "200" ]]; then
     SRC_URL_TMP="https://cs1.ip.thc.org"
   fi
   echo -e "\n[+] Server ==> ${SRC_URL_TMP}"
  #Download
   for I_D in "${I_DATES[@]}"; do 
    echo -e "\n[+] Processing ${I_D}"
     #Set
      unset GHCRPKG_TAG INPUT_TMP NO_GZ SRC_URL
      INPUT_TMP="$(echo "${I_D}" | tr -d '[:space:]')"
      if [[ "${INPUT_TMP}" == "$(date --utc -d "-1 day" '+%Y-%m-%d' | tr -d '[:space:]')" ]]; then
        #NO_GZ="TRUE"
        #SRC_URL="${SRC_URL_TMP}/${INPUT_TMP}.txt"
        SRC_URL="${SRC_URL_TMP}/${INPUT_TMP}.txt.gz"
      else
        SRC_URL="${SRC_URL_TMP}/${INPUT_TMP}.txt.gz"
      fi
     #Get
      for i in {1..2}; do
        #if [[ "${NO_GZ}" == "TRUE" ]]; then
        #  curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "${SRC_URL}" --retry 3 --retry-all-errors -o "${TMPDIR}/${I_D}.txt"
        #  if [[ -s "${TMPDIR}/${I_D}.txt" && $(stat -c%s "${TMPDIR}/${I_D}.txt") -gt 1000000 ]]; then
        #     du -sh "${TMPDIR}/${I_D}.txt"
        #     #Copy
        #       rm -rf "${ORAS_LOCAL}/DATA/certstream" 2>/dev/null
        #       mkdir -p "${ORAS_LOCAL}/DATA/certstream"
        #       cp -fv "${TMPDIR}/${I_D}.txt" "${ORAS_LOCAL}/DATA/certstream/${I_D}.txt"
        #     #Upload
        #       sync_to_ghcr
        #     #Break
        #       pushd "${TMPDIR}" &>/dev/null ; break
        #  else
        #     echo "Retrying... ${i}/2"
        #    sleep 2
        #  fi
        #else
          curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "${SRC_URL}" --retry 3 --retry-all-errors -o "${TMPDIR}/${I_D}.txt.gz"
          if [[ -s "${TMPDIR}/${I_D}.txt.gz" && $(stat -c%s "${TMPDIR}/${I_D}.txt.gz") -gt 1000000 ]]; then
             du -sh "${TMPDIR}/${I_D}.txt.gz"
             #Extract
               7z x "${TMPDIR}/${I_D}.txt.gz"
             #Copy
               if [[ ! -s "${TMPDIR}/${I_D}.txt" || $(stat -c%s "${TMPDIR}/${I_D}.txt") -lt 1000000 ]]; then
                 echo -e "[-] FATAL: Failed to Extract ${TMPDIR}/${I_D}.txt.gz ==> ${TMPDIR}/${I_D}.txt"
                 mv -fv "${TMPDIR}/${I_D}.txt.gz" "${SYSTMP}/DATA"
                break
               else
                 rm -rf "${ORAS_LOCAL}/DATA/certstream" 2>/dev/null
                 mkdir -p "${ORAS_LOCAL}/DATA/certstream"
                 cp -fv "${TMPDIR}/${I_D}.txt" "${ORAS_LOCAL}/DATA/certstream/${I_D}.txt"
                 cp -fv "${TMPDIR}/${I_D}.txt.gz" "${ORAS_LOCAL}/DATA/certstream/${I_D}.txt.gz"
                 ls "${ORAS_LOCAL}/DATA/certstream"
               fi
             #Upload
               sync_to_ghcr
             #Break
               pushd "${TMPDIR}" &>/dev/null ; break
          else
             echo "Retrying... ${i}/2"
            sleep 2
          fi
        #fi
      done
   done
else
  echo -e "\n[-] FATAL: Failed to Set Dates\n"
  echo -e "[+] Date (Pre Filter): ${I_DATES_TMP[*]}"
  echo -e "[+] Date (Post Filter): ${I_DATES[*]}"
  echo -e "[+] Date (Exists): ${GHCR_EXISTS[*]}"
 exit 1
fi
#-------------------------------------------------------#
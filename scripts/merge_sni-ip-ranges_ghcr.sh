#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to merge sni-ip-ranges ==> GHCR
## Self: https://raw.githubusercontent.com/pkgforge-security/domains/refs/heads/main/scripts/merge_sni-ip-ranges_ghcr.sh
#-------------------------------------------------------#

#-------------------------------------------------------#
##Sanity
if ! command -v anew-rs &> /dev/null; then
  echo -e "[-] Failed to find anew-rs\n"
 exit 1
fi
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
  [[ "$(du -s "${ORAS_LOCAL}/DATA/sni-ip-ranges" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 1000 ]]; then
  pushd "${ORAS_LOCAL}" &>/dev/null &&\
   unset GHCRPKG_TAG MODTIME_TEMP
   MODTIME="$(date --utc '+%Y-%m-%d_T%H-%M-%S' | sed 's/ZZ\+/Z/Ig' | tr -d '[:space:]')"
   GHCRPKG_TAG="$(echo "merged-${MODTIME}" | sed 's/[^a-zA-Z0-9._-]/_/g; s/_*$//')"
   export GHCRPKG_TAG MODTIME
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
        ghcr_push+=(--annotation "org.opencontainers.image.description=sni-ip-ranges-data-merged-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.documentation=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.licenses=blessing")
        ghcr_push+=(--annotation "org.opencontainers.image.ref.name=merged-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.revision=merged-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.source=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.title=sni-ip-ranges-merged-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.url=${SRC_URL}")
        ghcr_push+=(--annotation "org.opencontainers.image.vendor=pkgforge-security")
        ghcr_push+=(--annotation "org.opencontainers.image.version=merged-${MODTIME}")
        ghcr_push+=("${GHCRPKG_URL}:${GHCRPKG_TAG},merged")
        pushd "${ORAS_LOCAL}/DATA/sni-ip-ranges" &>/dev/null
        oras_files=() ; mapfile -t oras_files < <(find "." -maxdepth 1 -type f -not -path "*/\.*" -print 2>/dev/null)
         for o_f in "${oras_files[@]}"; do
           [[ -f "${o_f}" && -s "${o_f}" ]] && ghcr_push+=("${o_f}")
         done
        "${ghcr_push[@]}" ; sleep 5
       #Check
        if [[ "$(oras manifest fetch "${GHCRPKG_URL}:${GHCRPKG_TAG}" | jq -r '.annotations["dev.pkgforge-security.domains.upload_date"]' | tr -d '[:space:]')" == "${PKG_DATE}" ]]; then
          echo -e "\n[+] Registry --> https://${GHCRPKG_URL}"
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
#https://huggingface.co/datasets/pkgforge-security/domains/tree/main/DATA/sni-ip-ranges
pushd "${TMPDIR}" &>/dev/null
 I_SRCS=(amazon digitalocean google microsoft oracle)
 echo -e "\n[+] Data: ${I_SRCS[*]}\n"
 if [[ -n "${I_SRCS[*]}" && "${#I_SRCS[@]}" -ge 1 ]]; then
  #Check
   unset I_D SRC_URL_STATUS SRC_URL_TMP
   SRC_URL_TMP="https://huggingface.co/datasets/pkgforge-security/domains/tree/main/DATA/sni-ip-ranges"
   SRC_URL_STATUS="$(curl -X "HEAD" -qfksSL "${SRC_URL_TMP}" -I | sed -n 's/^[[:space:]]*HTTP\/[0-9.]*[[:space:]]\+\([0-9]\+\).*/\1/p' | tail -n1 | tr -d '[:space:]')"
   if echo "${SRC_URL_STATUS}" | grep -qiv '200$'; then
      SRC_URL_STATUS="$(curl -A "${USER_AGENT}" -X "HEAD" -qfksSL "${SRC_URL_TMP}" -I | sed -n 's/^[[:space:]]*HTTP\/[0-9.]*[[:space:]]\+\([0-9]\+\).*/\1/p' | tail -n1 | tr -d '[:space:]')"
      echo -e "\n[-] FATAL: Server seems to be Offline\n"
      curl -A "${USER_AGENT}" -w "(SERVER) <== %{url}\n" -X "HEAD" -qfksSL "${SRC_URL_TMP}" -I ; echo -e "\n"
     exit 1
   elif [[ "${SRC_URL_STATUS}" == "200" ]]; then
     SRC_URL="https://huggingface.co/datasets/pkgforge-security/domains/resolve/main/DATA/sni-ip-ranges"
   fi
   echo -e "\n[+] Server ==> ${SRC_URL_TMP}"
  #Download
   for I_D in "${I_SRCS[@]}"; do 
    echo -e "\n[+] Processing ${I_D}"
     #Set
      unset INPUT_TMP
      INPUT_TMP="$(echo "${I_D}" | tr -d '[:space:]')"
     #Get
      for i in {1..2}; do
        curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "${SRC_URL}/${I_D}.txt" --retry 3 --retry-all-errors -o "${TMPDIR}/${I_D}.txt"
        if [[ -s "${TMPDIR}/${I_D}.txt" && $(stat -c%s "${TMPDIR}/${I_D}.txt") -gt 1000 ]]; then
           du -sh "${TMPDIR}/${I_D}.txt"
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

#-------------------------------------------------------#
#Main
pushd "${TMPDIR}" &>/dev/null
 unset I_F I_FILES
 I_FILES=("${TMPDIR}/amazon.txt" "${TMPDIR}/digitalocean.txt" "${TMPDIR}/google.txt" "${TMPDIR}/microsoft.txt" "${TMPDIR}/oracle.txt")
#Check & Merge
 rm -rf "${ORAS_LOCAL}/DATA/sni-ip-ranges" 2>/dev/null
 mkdir -p "${ORAS_LOCAL}/DATA/sni-ip-ranges"
 for I_F in "${I_FILES[@]}"; do
   if [[ -f "${I_F}" ]] && [[ -s "${I_F}" ]]; then
     du -sh "${I_F}"
     echo -e "[+] Appending ${I_F} ==> ${ORAS_LOCAL}/DATA/sni-ip-ranges/all.txt"
     cat "${I_F}" | anew-rs -q "${ORAS_LOCAL}/DATA/sni-ip-ranges/all.txt"
     du -sh "${ORAS_LOCAL}/DATA/sni-ip-ranges/all.txt"
   else
     echo -e "\n[-] FATAL: Failed to Find ${I_F}"
     exit 1
   fi
 done
#Filter Domains
 if [[ -s "${ORAS_LOCAL}/DATA/sni-ip-ranges/all.txt" && $(stat -c%s "${ORAS_LOCAL}/DATA/sni-ip-ranges/all.txt") -gt 100000 ]]; then
  echo -e "[+] Cleaning up & Merging ${ORAS_LOCAL}/DATA/sni-ip-ranges/all.txt ==> ${ORAS_LOCAL}/DATA/sni-ip-ranges/domains.txt"
  sort --version-sort --unique "${ORAS_LOCAL}/DATA/sni-ip-ranges/all.txt" --output "${ORAS_LOCAL}/DATA/sni-ip-ranges/all.txt"
  cat "${ORAS_LOCAL}/DATA/sni-ip-ranges/all.txt" | sed '/^[[:space:]]*#/d' |\
    awk -F '[[:space:]]*--[[:space:]]*\\[|\\]' '{print $2}' | tr -s '[:space:]' '\n' |\
    sed -E 's/[[:space:]]+//g; s/^.*\*\.\s*|\s*$//' |\
    sed -E '/^[[:space:]]*$/d; s/^[[:space:]]*\*\.?[[:space:]]*//; s/[A-Z]/\L&/g' |\
    sed -E '/([0-9].*){40}/d; s/^[[:space:]]*//; s/[[:space:]]*$//; s/[${}%]//g' | sed 's/[()]//g' |\
    sed "s/'//g" | sed 's/"//g' | sed 's/^\.\(.*\)/\1/' | sed 's/^\*//' | sed 's/^\.\(.*\)/\1/' |\
    sed 's/^\*//' | sed 's/^\.\(.*\)/\1/' | sed 's/^\*//' | sed '/\./!d' | sed 's/^\.\(.*\)/\1/' |\
    sed '/[[:cntrl:]]/d' | sed '/!/d' | sed '/[^[:alnum:][:space:]._-]/d' | sed '/\*/d' |\
    sed '/^[^[:alnum:]]/d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort -u -o "${ORAS_LOCAL}/DATA/sni-ip-ranges/domains.txt"
    sort --version-sort --unique "${ORAS_LOCAL}/DATA/sni-ip-ranges/domains.txt" --output "${ORAS_LOCAL}/DATA/sni-ip-ranges/domains.txt"
    du -sh "${ORAS_LOCAL}/DATA/sni-ip-ranges/domains.txt"
    if [[ -s "${ORAS_LOCAL}/DATA/sni-ip-ranges/domains.txt" ]] && \
    [[ "$(wc -l < "${ORAS_LOCAL}/DATA/sni-ip-ranges/domains.txt" | tr -cd '0-9')" -gt 100000 ]]; then
      echo "[+] Domains: $(wc -l < ${ORAS_LOCAL}/DATA/sni-ip-ranges/domains.txt)"
      #Upload
       sync_to_ghcr
      #Break
       pushd "${TMPDIR}" &>/dev/null
    else
      echo -e "\n[X] FATAL: Failed to generate Domains\n"
      wc -l < "${ORAS_LOCAL}/DATA/sni-ip-ranges/domains.txt"
     exit 1 
    fi
 else
    echo -e "\n[X] FATAL: Failed to merge Data\n"
    du -sh "${ORAS_LOCAL}/DATA/sni-ip-ranges/all.txt" 
   exit 1
 fi
#-------------------------------------------------------#
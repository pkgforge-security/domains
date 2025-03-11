#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Sync nrd ==> HF
## Self: https://raw.githubusercontent.com/pkgforge-security/domains/refs/heads/main/scripts/sync_nrd_ghcr_hf.sh
#-------------------------------------------------------#


#-------------------------------------------------------#
##Sanity
if ! command -v anew-rs &> /dev/null; then
  echo -e "[-] Failed to find anew-rs\n"
 exit 1
fi
if ! command -v huggingface-cli &> /dev/null; then
  echo -e "[-] Failed to find huggingface-cli\n"
 exit 1 
fi
if [ -z "${HF_TOKEN+x}" ] || [ -z "${HF_TOKEN##*[[:space:]]}" ]; then
  echo -e "\n[-] FATAL: Failed to Find HF Token (\${HF_TOKEN}\n"
 exit 1
else
  export GIT_TERMINAL_PROMPT="0"
  export GIT_ASKPASS="/bin/echo"
  git config --global "credential.helper" store
  git config --global "user.email" "AjamX101@gmail.com"
  git config --global "user.name" "Azathothas"
  huggingface-cli login --token "${HF_TOKEN}" --add-to-git-credential
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
##Oras
 GHCRPKG_URL="ghcr.io/pkgforge-security/domains/nrd"
 PKG_WEBPAGE="$(echo "https://github.com/pkgforge-security/domains" | sed 's|^/*||; s|/*$||' | tr -d '[:space:]')"
 export GHCRPKG_URL PKG_WEBPAGE
##Repo
pushd "$(mktemp -d)" &>/dev/null && git clone --filter="blob:none" --depth="1" --no-checkout "https://huggingface.co/datasets/pkgforge-security/domains" && cd "./domains"
 git sparse-checkout set "" 
 git sparse-checkout set --no-cone --sparse-index "/README.md"
 git checkout ; unset HF_REPO_LOCAL ; HF_REPO_LOCAL="$(realpath .)" && export HF_REPO_LOCAL="${HF_REPO_LOCAL}"
 if [ ! -d "${HF_REPO_LOCAL}" ] || [ "$(du -s "${HF_REPO_LOCAL}" | cut -f1 | tr -d '[:space:]')" -le 100 ]; then
   echo -e "\n[X] FATAL: Failed to clone HF Repo\n"
  exit 1
 else
   git lfs install &>/dev/null ; huggingface-cli lfs-enable-largefiles "." &>/dev/null
 fi
popd &>/dev/null
#-------------------------------------------------------#

#-------------------------------------------------------#
##Func
sync_to_ghcr()
{
 if [[ -d "${HF_REPO_LOCAL}/DATA/nrd" ]] && \
  [[ "$(du -s "${HF_REPO_LOCAL}/DATA/nrd" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 1000 ]]; then
  pushd "${HF_REPO_LOCAL}" &>/dev/null &&\
   unset GHCRPKG_TAG MODTIME
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
        pushd "${HF_REPO_LOCAL}" &>/dev/null
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
        ghcr_push+=(--annotation "org.opencontainers.image.description=nrd-data-merged-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.documentation=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.licenses=blessing")
        ghcr_push+=(--annotation "org.opencontainers.image.ref.name=merged-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.revision=merged-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.source=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.title=nrd-merged-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.url=${SRC_URL}")
        ghcr_push+=(--annotation "org.opencontainers.image.vendor=pkgforge-security")
        ghcr_push+=(--annotation "org.opencontainers.image.version=merged-${MODTIME}")
        ghcr_push+=("${GHCRPKG_URL}:${GHCRPKG_TAG},merged")
        pushd "${HF_REPO_LOCAL}/DATA/nrd" &>/dev/null
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
  du -sh "${HF_REPO_LOCAL}/DATA/nrd" && realpath "${HF_REPO_LOCAL}/DATA/nrd"
 fi
}
export -f sync_to_ghcr
#-------------------------------------------------------#

#-------------------------------------------------------#
##Func
sync_to_hf() 
{
 if [[ -d "${HF_REPO_LOCAL}/DATA/nrd" ]] && \
  [[ "$(du -s "${HF_REPO_LOCAL}/DATA/nrd" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 1000 ]]; then
  pushd "${HF_REPO_LOCAL}" &>/dev/null &&\
    git remote -v
    COMMIT_MSG="[+] Newly Registered Domains (NRD)"
    git sparse-checkout set ""
    git sparse-checkout set --no-cone --sparse-index "/README.md"
    git checkout
    git pull origin main
    git pull origin main --ff-only || git pull --rebase origin main
    git merge --no-ff -m "Merge & Sync"
    git fetch origin main
    find "./DATA/nrd" -maxdepth 1 -type f -not -path "*/\.*" -exec basename "{}" \; | xargs -I "{}" git sparse-checkout add "DATA/nrd/{}"
    git lfs track "./DATA/nrd/**"
    git sparse-checkout list 2>/dev/null
    git lfs untrack '.gitattributes' 2>/dev/null
    sed '/\*/!d' -i '.gitattributes'
    find "./DATA/nrd" -maxdepth 1 -type f -not -path "*/\.*" | xargs -I "{}" git add "{}" --verbose
    git add --all --renormalize --verbose
    git commit -m "${COMMIT_MSG}"
    pushd "${HF_REPO_LOCAL}" &>/dev/null
     retry_git_push()
      {
       for i in {1..5}; do
        #Generic Merge
         git pull origin main --ff-only || git pull --rebase origin main
         git merge --no-ff -m "${COMMIT_MSG}"
        #Push
         git pull origin main 2>/dev/null
         if git push -u origin main; then
            echo -e "\n[+] Pushed ==> [https://huggingface.co/datasets/pkgforge-security/domains/tree/main/DATA/nrd/]\n"
            echo "ARTIFACTS_PATH=${HF_REPO_LOCAL}/DATA/nrd" >> "${GITHUB_ENV}" 2>/dev/null
            break
         fi
        #Sleep randomly 
         sleep "$(shuf -i 500-4500 -n 1)e-3"
       done
      }
      export -f retry_git_push
      retry_git_push
      git --no-pager log '-1' --pretty="format:'%h - %ar - %s - %an'"
      if ! git ls-remote --heads origin | grep -qi "$(git rev-parse HEAD)"; then
       echo -e "\n[-] WARN: Failed to push ==> ${UPDATED_AT}\n(Retrying ...)\n"
       retry_git_push
       git --no-pager log '-1' --pretty="format:'%h - %ar - %s - %an'"
       if ! git ls-remote --heads origin | grep -qi "$(git rev-parse HEAD)"; then
         echo -e "\n[-] FATAL: Failed to push ==> ${UPDATED_AT}\n"
         retry_git_push
       fi
      fi
  du -sh "${HF_REPO_LOCAL}/DATA/nrd" && realpath "${HF_REPO_LOCAL}/DATA/nrd"
 fi
}
export -f sync_to_hf
#-------------------------------------------------------#

#-------------------------------------------------------#
##SRC//DEST
rm -rf "${HF_REPO_LOCAL}/DATA/nrd" 2>/dev/null
mkdir -p "${HF_REPO_LOCAL}/DATA/nrd"
pushd "${TMPDIR}" &>/dev/null
#https://github.com/cenk/nrd [10 Days]
 for i in {1..2}; do
   curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "https://raw.githubusercontent.com/cenk/nrd/refs/heads/main/nrd-last-10-days.txt" --retry 3 --retry-all-errors -o "${TMPDIR}/NRD_10.txt"
    if [[ -s "${TMPDIR}/NRD_10.txt" && $(stat -c%s "${TMPDIR}/NRD_10.txt") -gt 10000 ]]; then
      du -sh "${TMPDIR}/NRD_10.txt"
     break
    else
       echo "Retrying... ${i}/2"
      sleep 2
    fi
 done
#https://github.com/cenk/nrd [20 Days]
 for i in {1..2}; do
   curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "https://raw.githubusercontent.com/cenk/nrd/refs/heads/main/nrd-last-20-days.txt" --retry 3 --retry-all-errors -o "${TMPDIR}/NRD_20.txt"
    if [[ -s "${TMPDIR}/NRD_20.txt" && $(stat -c%s "${TMPDIR}/NRD_20.txt") -gt 10000 ]]; then
      du -sh "${TMPDIR}/NRD_20.txt"
     break
    else
       echo "Retrying... ${i}/2"
      sleep 2
    fi
 done
#https://github.com/cenk/nrd [30 Days]
 for i in {1..2}; do
   curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "https://raw.githubusercontent.com/cenk/nrd/refs/heads/main/nrd-last-30-days.txt" --retry 3 --retry-all-errors -o "${TMPDIR}/NRD_30.txt"
    if [[ -s "${TMPDIR}/NRD_30.txt" && $(stat -c%s "${TMPDIR}/NRD_30.txt") -gt 10000 ]]; then
      du -sh "${TMPDIR}/NRD_30.txt"
     break
    else
       echo "Retrying... ${i}/2"
      sleep 2
    fi
 done
#https://github.com/xRuffKez/NRD [14 Days] 
 for i in {1..2}; do
   curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "https://github.com/xRuffKez/NRD/raw/refs/heads/main/lists/14-day/domains-only/nrd-14day.txt" --retry 3 --retry-all-errors -o "${TMPDIR}/NRD_14.txt"
    if [[ -s "${TMPDIR}/NRD_14.txt" && $(stat -c%s "${TMPDIR}/NRD_14.txt") -gt 10000 ]]; then
      du -sh "${TMPDIR}/NRD_14.txt"
     break
    else
       echo "Retrying... ${i}/2"
      sleep 2
    fi
 done
#https://github.com/xRuffKez/NRD [30 Days-1]
 for i in {1..2}; do
   curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "https://raw.githubusercontent.com/xRuffKez/NRD/refs/heads/main/lists/30-day/domains-only/nrd-30day_part1.txt" --retry 3 --retry-all-errors -o "${TMPDIR}/NRD_30_1.txt"
    if [[ -s "${TMPDIR}/NRD_30_1.txt" && $(stat -c%s "${TMPDIR}/NRD_30_1.txt") -gt 10000 ]]; then
      du -sh "${TMPDIR}/NRD_30_1.txt"
     break
    else
       echo "Retrying... ${i}/2"
      sleep 2
    fi
 done
#https://github.com/xRuffKez/NRD [30 Days-2]
 for i in {1..2}; do
   curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "https://raw.githubusercontent.com/xRuffKez/NRD/refs/heads/main/lists/30-day/domains-only/nrd-30day_part2.txt" --retry 3 --retry-all-errors -o "${TMPDIR}/NRD_30_2.txt"
    if [[ -s "${TMPDIR}/NRD_30_2.txt" && $(stat -c%s "${TMPDIR}/NRD_30_2.txt") -gt 10000 ]]; then
      du -sh "${TMPDIR}/NRD_30_2.txt"
     break
    else
       echo "Retrying... ${i}/2"
      sleep 2
    fi
 done
#-------------------------------------------------------#

#-------------------------------------------------------#
cleanup_domains()
{
 set -x ; echo -e "\n"
 echo -e "\n" && time sed -E '/^[[:space:]]*$/d; s/^[[:space:]]*\*\.?[[:space:]]*//; s/[A-Z]/\L&/g' -i "$1"
 echo -e "\n" && time sed -E '/([0-9].*){40}/d; s/^[[:space:]]*//; s/[[:space:]]*$//; s/[${}%]//g' -i "$1"
 echo -e "\n" && time sed 's/[()]//g' -i "$1"
 echo -e "\n" && time sed "s/'//g" -i "$1"
 echo -e "\n" && time sed 's/"//g' -i "$1"
 echo -e "\n" && time sed 's/^\.\(.*\)/\1/' -i "$1"
 echo -e "\n" && time sed 's/^\*//' -i "$1"
 echo -e "\n" && time sed 's/^\.\(.*\)/\1/' -i "$1"
 echo -e "\n" && time sed 's/^\*//' -i "$1"
 echo -e "\n" && time sed 's/^\.\(.*\)/\1/' -i "$1"
 echo -e "\n" && time sed 's/^\*//' -i "$1"
 echo -e "\n" && time sed '/\./!d' -i "$1"
 echo -e "\n" && time sed 's/^\.\(.*\)/\1/' -i "$1"
 echo -e "\n" && time sed '/[[:cntrl:]]/d' -i "$1"
 echo -e "\n" && time sed '/!/d' -i "$1"
 echo -e "\n" && time sed '/[^[:alnum:][:space:]._-]/d' -i "$1"
 echo -e "\n" && time sed '/\*/d' -i "$1"
 echo -e "\n" && time sed '/^[^[:alnum:]]/d' -i "$1"
 echo -e "\n" && time sed 's/^[[:space:]]*//;s/[[:space:]]*$//' -i "$1"
 set +x ; echo -e "\n"
}
export -f cleanup_domains
#-------------------------------------------------------#

#-------------------------------------------------------# 
##Main 
pushd "${TMPDIR}" &>/dev/null && export DOMAIN_SRC="nrd"
 #Merge
  if [[ $(stat -c%s "${TMPDIR}/NRD_10.txt") -gt 10000 && $(stat -c%s "${TMPDIR}/NRD_14.txt") -gt 10000 ]]; then
    sort -u "${TMPDIR}/NRD_10.txt" -o "${TMPDIR}/10_days.txt"
    cat "${TMPDIR}/10_days.txt" "${TMPDIR}/NRD_14.txt" 2>/dev/null | sed '/^[[:space:]]*#/d' | anew-rs -q "${TMPDIR}/14_days.txt"
    du -sh "${TMPDIR}/14_days.txt"
  fi
  if [[ $(stat -c%s "${TMPDIR}/14_days.txt") -gt 10000 && $(stat -c%s "${TMPDIR}/NRD_20.txt") -gt 10000 ]]; then
    cat "${TMPDIR}/14_days.txt" "${TMPDIR}/NRD_20.txt" 2>/dev/null | sed '/^[[:space:]]*#/d' | anew-rs -q "${TMPDIR}/20_days.txt"
    du -sh "${TMPDIR}/20_days.txt"
  fi
  if [[ $(stat -c%s "${TMPDIR}/NRD_30.txt") -gt 10000 &&\
     $(stat -c%s "${TMPDIR}/NRD_30_1.txt") -gt 10000 &&\
     $(stat -c%s "${TMPDIR}/NRD_30_2.txt") -gt 10000 ]]; then
    cat "${TMPDIR}/NRD_30.txt" "${TMPDIR}/NRD_30_1.txt" "${TMPDIR}/NRD_30_2.txt" 2>/dev/null | sed '/^[[:space:]]*#/d' | anew-rs -q "${TMPDIR}/30_days.txt"
    du -sh "${TMPDIR}/30_days.txt"
  fi
 #Parse & Copy
  if [[ $(stat -c%s "${TMPDIR}/10_days.txt") -gt 10000 ]]; then
   cat "${TMPDIR}/10_days.txt" | sed '/^[[:space:]]*#/d' | tr -s '[:space:]' '\n' > "${HF_REPO_LOCAL}/DATA/nrd/10_days.txt"
   cleanup_domains "${HF_REPO_LOCAL}/DATA/nrd/10_days.txt"
   sort --version-sort --unique "${HF_REPO_LOCAL}/DATA/nrd/10_days.txt" --output "${HF_REPO_LOCAL}/DATA/nrd/10_days.txt"
   du -sh "${HF_REPO_LOCAL}/DATA/nrd/10_days.txt"
   echo "[+] Domains: $(wc -l < ${HF_REPO_LOCAL}/DATA/nrd/10_days.txt)"
  fi
  if [[ $(stat -c%s "${TMPDIR}/14_days.txt") -gt 10000 ]]; then
   cat "${TMPDIR}/14_days.txt" | sed '/^[[:space:]]*#/d' | tr -s '[:space:]' '\n' > "${HF_REPO_LOCAL}/DATA/nrd/14_days.txt"
   cleanup_domains "${HF_REPO_LOCAL}/DATA/nrd/14_days.txt"
   sort --version-sort --unique "${HF_REPO_LOCAL}/DATA/nrd/14_days.txt" --output "${HF_REPO_LOCAL}/DATA/nrd/14_days.txt"
   du -sh "${HF_REPO_LOCAL}/DATA/nrd/14_days.txt"
   echo "[+] Domains: $(wc -l < ${HF_REPO_LOCAL}/DATA/nrd/14_days.txt)"
  fi
  if [[ $(stat -c%s "${TMPDIR}/20_days.txt") -gt 10000 ]]; then
   cat "${TMPDIR}/20_days.txt" | sed '/^[[:space:]]*#/d' | tr -s '[:space:]' '\n' > "${HF_REPO_LOCAL}/DATA/nrd/20_days.txt"
   cleanup_domains "${HF_REPO_LOCAL}/DATA/nrd/20_days.txt"
   sort --version-sort --unique "${HF_REPO_LOCAL}/DATA/nrd/20_days.txt" --output "${HF_REPO_LOCAL}/DATA/nrd/20_days.txt"
   du -sh "${HF_REPO_LOCAL}/DATA/nrd/20_days.txt"
   echo "[+] Domains: $(wc -l < ${HF_REPO_LOCAL}/DATA/nrd/20_days.txt)"
  fi
  if [[ $(stat -c%s "${TMPDIR}/30_days.txt") -gt 10000 ]]; then
   cat "${TMPDIR}/30_days.txt" | sed '/^[[:space:]]*#/d' | tr -s '[:space:]' '\n' > "${HF_REPO_LOCAL}/DATA/nrd/30_days.txt"
   cleanup_domains "${HF_REPO_LOCAL}/DATA/nrd/30_days.txt"
   sort --version-sort --unique "${HF_REPO_LOCAL}/DATA/nrd/30_days.txt" --output "${HF_REPO_LOCAL}/DATA/nrd/30_days.txt"
   du -sh "${HF_REPO_LOCAL}/DATA/nrd/30_days.txt"
   echo "[+] Domains: $(wc -l < ${HF_REPO_LOCAL}/DATA/nrd/30_days.txt)"
  fi
#Upload
 sync_to_ghcr
 sync_to_hf
#-------------------------------------------------------#
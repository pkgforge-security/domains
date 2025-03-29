#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to merge certstream ==> HF
## Self: https://raw.githubusercontent.com/pkgforge-security/domains/refs/heads/main/scripts/merge_certstream_ghcr_hf.sh
#-------------------------------------------------------#

#-------------------------------------------------------#
##Sanity
if ! command -v anew-rs &> /dev/null; then
  echo -e "[-] Failed to find anew-rs\n"
 exit 1
fi
if ! command -v duplicut &> /dev/null; then
  echo -e "[-] Failed to find duplicut\n"
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
 GHCRPKG_URL="ghcr.io/pkgforge-security/domains/certstream"
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
 if [[ -d "${HF_REPO_LOCAL}/DATA/certstream" ]] && \
  [[ "$(du -s "${HF_REPO_LOCAL}/DATA/certstream" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 1000 ]]; then
  pushd "${HF_REPO_LOCAL}" &>/dev/null &&\
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
        ghcr_push+=(--annotation "org.opencontainers.image.description=certstream-data-merged-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.documentation=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.licenses=blessing")
        ghcr_push+=(--annotation "org.opencontainers.image.ref.name=merged-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.revision=merged-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.source=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.title=certstream-merged-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.url=${SRC_URL}")
        ghcr_push+=(--annotation "org.opencontainers.image.vendor=pkgforge-security")
        ghcr_push+=(--annotation "org.opencontainers.image.version=merged-${MODTIME}")
        ghcr_push+=("${GHCRPKG_URL}:${GHCRPKG_TAG},merged")
        pushd "${HF_REPO_LOCAL}/DATA/certstream" &>/dev/null
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
  du -sh "${HF_REPO_LOCAL}/DATA/certstream" && realpath "${HF_REPO_LOCAL}/DATA/certstream"
 fi
}
export -f sync_to_ghcr
#-------------------------------------------------------#

#-------------------------------------------------------#
##Func
sync_to_hf() 
{
 if [[ -d "${HF_REPO_LOCAL}/DATA/certstream" ]] && \
  [[ "$(du -s "${HF_REPO_LOCAL}/DATA/certstream" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 1000 ]]; then
  pushd "${HF_REPO_LOCAL}" &>/dev/null &&\
    git remote -v
    COMMIT_MSG="[+] certstream [Merged List]"
    git sparse-checkout set ""
    git sparse-checkout set --no-cone --sparse-index "/README.md"
    git checkout
    git pull origin main
    git pull origin main --ff-only || git pull --rebase origin main
    git merge --no-ff -m "Merge & Sync"
    git fetch origin main
    find "./DATA/certstream" -maxdepth 1 -type f -not -path "*/\.*" -exec basename "{}" \; | xargs -I "{}" git sparse-checkout add "DATA/certstream/{}"
    git lfs track "./DATA/certstream/**"
    git sparse-checkout list 2>/dev/null
    git lfs untrack '.gitattributes' 2>/dev/null
    sed '/\*/!d' -i '.gitattributes'
    find "./DATA/certstream" -maxdepth 1 -type f -not -path "*/\.*" | xargs -I "{}" git add "{}" --verbose
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
            echo -e "\n[+] Pushed ==> [https://huggingface.co/datasets/pkgforge-security/domains/tree/main/DATA/certstream/]\n"
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
       echo -e "\n[-] WARN: Failed to push ==> [Merged List]\n(Retrying ...)\n"
       retry_git_push
       git --no-pager log '-1' --pretty="format:'%h - %ar - %s - %an'"
       if ! git ls-remote --heads origin | grep -qi "$(git rev-parse HEAD)"; then
         echo -e "\n[-] FATAL: Failed to push ==> [Merged List]\n"
         retry_git_push
       fi
      fi
  du -sh "${HF_REPO_LOCAL}/DATA/certstream" && realpath "${HF_REPO_LOCAL}/DATA/certstream"
 fi
}
export -f sync_to_hf
#-------------------------------------------------------#

#-------------------------------------------------------#
##SRC//DEST
#https://huggingface.co/datasets/pkgforge-security/domains/tree/main/DATA/certstream
pushd "${TMPDIR}" &>/dev/null
 unset I_SRCS I_LATEST
 mapfile -t "I_SRCS" < <(for i in $(seq 1 $((10#$(date --utc +%d) - 0))); do date --utc -d "-${i} days" +%Y-%m-%d; done | sort --version-sort --unique | tail -n 7 | grep -oP '^\d{4}-\d{2}-\d{2}')
 I_LATEST="$(echo "${I_SRCS[*]}" | sort --version-sort --unique  | tail -n 1 | grep -oP '^\d{4}-\d{2}-\d{2}' | tr -d '[:space:]')"
 export I_LATEST
 echo -e "\n[+] Data: ${I_SRCS[*]}\n"
 if [[ -n "${I_SRCS[*]}" && "${#I_SRCS[@]}" -ge 1 ]]; then
  #Check
   unset I_D SRC_URL_STATUS SRC_URL_TMP
   SRC_URL_TMP="https://huggingface.co/datasets/pkgforge-security/domains/tree/main/DATA/certstream"
   SRC_URL_STATUS="$(curl -X "HEAD" -qfksSL "${SRC_URL_TMP}" -I | sed -n 's/^[[:space:]]*HTTP\/[0-9.]*[[:space:]]\+\([0-9]\+\).*/\1/p' | tail -n1 | tr -d '[:space:]')"
   if echo "${SRC_URL_STATUS}" | grep -qiv '200$'; then
      SRC_URL_STATUS="$(curl -A "${USER_AGENT}" -X "HEAD" -qfksSL "${SRC_URL_TMP}" -I | sed -n 's/^[[:space:]]*HTTP\/[0-9.]*[[:space:]]\+\([0-9]\+\).*/\1/p' | tail -n1 | tr -d '[:space:]')"
      echo -e "\n[-] FATAL: Server seems to be Offline\n"
      curl -A "${USER_AGENT}" -w "(SERVER) <== %{url}\n" -X "HEAD" -qfksSL "${SRC_URL_TMP}" -I ; echo -e "\n"
     exit 1
   elif [[ "${SRC_URL_STATUS}" == "200" ]]; then
     SRC_URL="https://huggingface.co/datasets/pkgforge-security/domains/resolve/main/DATA/certstream"
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
cleanup_domains()
{
 set -x ; echo -e "\n"
 echo -e "\n" && time sed -E '/^[[:space:]]*$/d' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed -E 's/[[:space:]]+//g; s/^.*\*\.\s*|\s*$//' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/^\*\.\(.*\)/\1/; s/^\*//' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/[A-Z]/\L&/g' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/^[[:space:]]*//;s/[[:space:]]*$//' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed '/:/d' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed -E '/^[[:space:]]*$/d; s/^[[:space:]]*\*\.?[[:space:]]*//; s/[A-Z]/\L&/g' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed -E '/([0-9].*){40}/d; s/^[[:space:]]*//; s/[[:space:]]*$//; s/[${}%]//g' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/[()]//g' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed "s/'//g" -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/"//g' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/^\.\(.*\)/\1/' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/^\*//' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/^\.\(.*\)/\1/' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/^\*//' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/^\.\(.*\)/\1/' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/^\*//' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed '/\./!d' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/^\.\(.*\)/\1/' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed '/[[:cntrl:]]/d' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed '/!/d' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed '/[^[:alnum:][:space:]._-]/d' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed '/\*/d' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed '/^[^[:alnum:]]/d' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sed 's/^[[:space:]]*//;s/[[:space:]]*$//' -i "$1" ; du -sh "$1"
 set +x ; echo -e "\n"
}
export -f cleanup_domains
#-------------------------------------------------------#

#-------------------------------------------------------#
#Main
pushd "${TMPDIR}" &>/dev/null
 unset I_F I_FILES
 rm -rf "${HF_REPO_LOCAL}/DATA/certstream" 2>/dev/null
 mkdir -p "${HF_REPO_LOCAL}/DATA/certstream" 
 mapfile -t "I_FILES" < <(printf "${TMPDIR}/%s.txt\n" "${I_SRCS[@]}")
#Check & Merge (Daily)
 du -sh "${TMPDIR}/${I_LATEST}.txt"
 echo -e "[+] Appending ${TMPDIR}/${I_LATEST}.txt ==> ${HF_REPO_LOCAL}/DATA/certstream/all_latest.txt"
 duplicut "${TMPDIR}/${I_LATEST}.txt" --line-max-size "255" --lowercase --outfile "${TMPDIR}/tmp.txt"
 cat "${TMPDIR}/tmp.txt" > "${HF_REPO_LOCAL}/DATA/certstream/all_latest.txt" && rm "${TMPDIR}/tmp.txt"
 du -sh "${HF_REPO_LOCAL}/DATA/certstream/all_latest.txt"
#Filter Domains [Daily]
 duplicut "${HF_REPO_LOCAL}/DATA/certstream/all_latest.txt" --line-max-size "255" --lowercase --outfile "${TMPDIR}/tmp.txt"
 mv -fv "${TMPDIR}/tmp.txt" "${HF_REPO_LOCAL}/DATA/certstream/all_latest.txt"
 if [[ -s "${HF_REPO_LOCAL}/DATA/certstream/all_latest.txt" && $(stat -c%s "${HF_REPO_LOCAL}/DATA/certstream/all_latest.txt") -gt 100000 ]]; then
  echo -e "[+] Cleaning up & Merging ${HF_REPO_LOCAL}/DATA/certstream/all_latest.txt ==> ${HF_REPO_LOCAL}/DATA/certstream/latest.txt"
  sort --version-sort --unique "${HF_REPO_LOCAL}/DATA/certstream/all_latest.txt" --output "${HF_REPO_LOCAL}/DATA/certstream/all_latest.txt"
  du -sh "${HF_REPO_LOCAL}/DATA/certstream/all_latest.txt"
  cat "${HF_REPO_LOCAL}/DATA/certstream/all_latest.txt" | sed '/^[[:space:]]*#/d' | tr -s '[:space:]' '\n' > "${HF_REPO_LOCAL}/DATA/certstream/latest.txt"
  echo -e "[+] Filtering ..."
   cleanup_domains "${HF_REPO_LOCAL}/DATA/certstream/latest.txt"
   sort --version-sort --unique "${HF_REPO_LOCAL}/DATA/certstream/latest.txt" --output "${HF_REPO_LOCAL}/DATA/certstream/latest.txt"
    du -sh "${HF_REPO_LOCAL}/DATA/certstream/latest.txt"
    if [[ -s "${HF_REPO_LOCAL}/DATA/certstream/latest.txt" && $(stat -c%s "${HF_REPO_LOCAL}/DATA/certstream/latest.txt") -gt 100000 ]]; then
      echo "[+] Domains: $(wc -l < ${HF_REPO_LOCAL}/DATA/certstream/latest.txt)"
      #Break
       pushd "${TMPDIR}" &>/dev/null
    else
      echo -e "\n[X] FATAL: Failed to generate Domains\n"
      wc -l < "${HF_REPO_LOCAL}/DATA/certstream/latest.txt"
     exit 1 
    fi
 fi
#Check & Merge (Weekly)
 for I_F in "${I_FILES[@]}"; do
   if [[ -f "${I_F}" ]] && [[ -s "${I_F}" ]]; then
     du -sh "${I_F}"
     echo -e "[+] Appending ${I_F} ==> ${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt"
     #cat "${I_F}" | anew-rs -q "${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt"
     duplicut "${I_F}" --line-max-size "255" --lowercase --outfile "${TMPDIR}/tmp.txt"
     cat "${TMPDIR}/tmp.txt" >> "${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt" && rm "${TMPDIR}/tmp.txt"
     du -sh "${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt"
   else
     echo -e "\n[-] FATAL: Failed to Find ${I_F}"
     exit 1
   fi
 done
#Filter Domains [Weekly]
 duplicut "${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt" --line-max-size "255" --lowercase --outfile "${TMPDIR}/tmp.txt"
 mv -fv "${TMPDIR}/tmp.txt" "${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt"
 if [[ -s "${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt" && $(stat -c%s "${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt") -gt 100000 ]]; then
  echo -e "[+] Cleaning up & Merging ${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt ==> ${HF_REPO_LOCAL}/DATA/certstream/weekly.txt"
  sort --version-sort --unique "${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt" --output "${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt"
  du -sh "${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt"
  cat "${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt" | sed '/^[[:space:]]*#/d' | tr -s '[:space:]' '\n' > "${HF_REPO_LOCAL}/DATA/certstream/weekly.txt"
  echo -e "[+] Filtering ..."
   cleanup_domains "${HF_REPO_LOCAL}/DATA/certstream/weekly.txt"
   sort --version-sort --unique "${HF_REPO_LOCAL}/DATA/certstream/weekly.txt" --output "${HF_REPO_LOCAL}/DATA/certstream/weekly.txt"
    du -sh "${HF_REPO_LOCAL}/DATA/certstream/weekly.txt"
    if [[ -s "${HF_REPO_LOCAL}/DATA/certstream/weekly.txt" && $(stat -c%s "${HF_REPO_LOCAL}/DATA/certstream/weekly.txt") -gt 100000 ]]; then
      #echo "[+] Domains: $(wc -l < ${HF_REPO_LOCAL}/DATA/certstream/weekly.txt)"
      #Break
       pushd "${TMPDIR}" &>/dev/null
    else
      echo -e "\n[X] FATAL: Failed to generate Domains\n"
      wc -l < "${HF_REPO_LOCAL}/DATA/certstream/weekly.txt"
     exit 1 
    fi
 else
    echo -e "\n[X] FATAL: Failed to merge Data\n"
    du -sh "${HF_REPO_LOCAL}/DATA/certstream/all_weekly.txt" 
   exit 1
 fi
#Upload
 sync_to_ghcr
 sync_to_hf
#-------------------------------------------------------#
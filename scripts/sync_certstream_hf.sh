#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Sync Certstream ==> HF
## Self: https://raw.githubusercontent.com/pkgforge-security/domains/refs/heads/main/scripts/sync_certstream_hf.sh
#-------------------------------------------------------#


#-------------------------------------------------------#
##Sanity
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
##ENV
export TZ="UTC"
SYSTMP="$(dirname $(mktemp -u))" && export SYSTMP="${SYSTMP}"
TMPDIR="$(mktemp -d)" && export TMPDIR="${TMPDIR}" ; echo -e "\n[+] Using TEMP: ${TMPDIR}\n"
rm -rf "${SYSTMP}/DATA" 2>/dev/null ; mkdir -p "${SYSTMP}/DATA"
if [[ -z "${USER_AGENT}" ]]; then
 USER_AGENT="$(curl -qfsSL 'https://raw.githubusercontent.com/pkgforge/devscripts/refs/heads/main/Misc/User-Agents/ua_firefox_macos_latest.txt')"
fi
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
sync_to_hf() 
{
 if [[ -d "${HF_REPO_LOCAL}/DATA/certstream" ]] && \
  [[ "$(du -s "${HF_REPO_LOCAL}/DATA/certstream" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 100000 ]]; then
  pushd "${HF_REPO_LOCAL}" &>/dev/null &&\
    git remote -v
    COMMIT_MSG="[+] CertStream [${I_D}]"
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
            echo -e "\n[+] Pushed ==> [https://huggingface.co/datasets/pkgforge-security/domains/tree/main/DATA/certstream/${I_D}]\n"
            echo "MERGE_DATA=YES" >> "${GITHUB_ENV}" 2>/dev/null
            cp -rfv "${HF_REPO_LOCAL}/DATA/certstream/." "${SYSTMP}/DATA"
            echo "ARTIFACTS_PATH=${HF_REPO_LOCAL}/DATA/certstream" >> "${GITHUB_ENV}" 2>/dev/null
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
       echo -e "\n[-] WARN: Failed to push ==> ${I_D}\n(Retrying ...)\n"
       retry_git_push
       git --no-pager log '-1' --pretty="format:'%h - %ar - %s - %an'"
       if ! git ls-remote --heads origin | grep -qi "$(git rev-parse HEAD)"; then
         echo -e "\n[-] FATAL: Failed to push ==> ${I_D}\n"
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
pushd "${TMPDIR}" &>/dev/null && export DOMAIN_SRC="certstream"
#CS data for the current day is available tomorrow @ 00:15 UTC
#mapfile -t "I_DATES" < <(for i in $(seq 0 $((10#$(date --utc +%d) - 1))); do date --utc -d "-${i} days" +%Y-%m-%d; done)
I_DATES_TMP=() ; mapfile -t "I_DATES_TMP" < <(for i in $(seq 1 $((10#$(date --utc +%d) - 0))); do date --utc -d "-${i} days" +%Y-%m-%d; done | sort --version-sort --unique)
HF_EXISTS=() ; mapfile -t "HF_EXISTS" < <(git -C "${HF_REPO_LOCAL}" ls-tree --name-only 'HEAD:DATA/certstream' 2>/dev/null | sort --version-sort --unique | sed 'N;$!P;$!D;$d' | sort -u)
I_DATES=() ; mapfile -t I_DATES < <(printf "%s\n" "${I_DATES_TMP[@]}" | grep -Fxv -f <(printf "%s\n" "${HF_EXISTS[@]}" | grep -oP '^\d{4}-\d{2}-\d{2}'))
echo -e "\n[+] Data: ${I_DATES[*]}\n"
if [[ -n "${I_DATES[*]}" && "${#I_DATES[@]}" -ge 1 ]]; then
  #Check
   unset I_D SRC_URL_STATUS SRC_URL_TMP
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
      unset INPUT_TMP NO_GZ SRC_URL TXT_FILE
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
        #       rm -rf "${HF_REPO_LOCAL}/DATA/certstream" 2>/dev/null
        #       mkdir -p "${HF_REPO_LOCAL}/DATA/certstream"
        #       cp -fv "${TMPDIR}/${I_D}.txt" "${HF_REPO_LOCAL}/DATA/certstream/${I_D}.txt"
        #     #Upload
        #       sync_to_hf
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
               TXT_FILE="$(find "${TMPDIR}" -type f -exec file -i "{}" \; | grep -Ei "text/plain" | cut -d":" -f1 | xargs realpath | grep -i "${I_D}" | tr -d '[:space:]')"
             #Copy
               if [[ ! -s "${TXT_FILE}" || $(stat -c%s "${TXT_FILE}") -lt 1000000 ]]; then
                 echo -e "[-] FATAL: Failed to Extract ${TMPDIR}/${I_D}.txt.gz ==> ${TXT_FILE}"
                 mv -fv "${TMPDIR}/${I_D}.txt.gz" "${SYSTMP}/DATA"
                break
               else
                 rm -rf "${HF_REPO_LOCAL}/DATA/certstream" 2>/dev/null
                 mkdir -p "${HF_REPO_LOCAL}/DATA/certstream"
                 cp -fv "${TXT_FILE}" "${HF_REPO_LOCAL}/DATA/certstream/${I_D}.txt"
                 cp -fv "${TMPDIR}/${I_D}.txt.gz" "${HF_REPO_LOCAL}/DATA/certstream/${I_D}.txt.gz"
                 ls "${HF_REPO_LOCAL}/DATA/certstream"
               fi
             #Upload
               sync_to_hf
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
  echo -e "[+] Date (Exists): ${HF_EXISTS[*]}"
 exit 1
fi
#-------------------------------------------------------#
#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Sync trickest ==> HF
## Self: https://raw.githubusercontent.com/pkgforge-security/domains/refs/heads/main/scripts/sync_trickest_hf.sh
#-------------------------------------------------------#


#-------------------------------------------------------#
##Sanity
if ! command -v dasel &> /dev/null; then
  echo -e "[-] Failed to find dasel\n"
 exit 1 
fi
if ! command -v huggingface-cli &> /dev/null; then
  echo -e "[-] Failed to find huggingface-cli\n"
 exit 1 
fi
if ! command -v qsv &> /dev/null; then
  echo -e "[-] Failed to find qsv\n"
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
 if [[ -d "${HF_REPO_LOCAL}/DATA/trickest" ]] && \
  [[ "$(du -s "${HF_REPO_LOCAL}/DATA/trickest" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 1000 ]]; then
  pushd "${HF_REPO_LOCAL}" &>/dev/null &&\
    git remote -v
    COMMIT_MSG="[+] trickest [${COMMIT_HASH}] (${UPDATED_AT})"
    git sparse-checkout set ""
    git sparse-checkout set --no-cone --sparse-index "/README.md"
    git checkout
    git pull origin main
    git pull origin main --ff-only || git pull --rebase origin main
    git merge --no-ff -m "Merge & Sync"
    git fetch origin main
    find "./DATA/trickest" -maxdepth 1 -type f -not -path "*/\.*" -exec basename "{}" \; | xargs -I "{}" git sparse-checkout add "DATA/trickest/{}"
    git lfs track "./DATA/trickest/**"
    git sparse-checkout list 2>/dev/null
    git lfs untrack '.gitattributes' 2>/dev/null
    sed '/\*/!d' -i '.gitattributes'
    find "./DATA/trickest" -maxdepth 1 -type f -not -path "*/\.*" | xargs -I "{}" git add "{}" --verbose
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
            echo -e "\n[+] Pushed ==> [https://huggingface.co/datasets/pkgforge-security/domains/tree/main/DATA/trickest/]\n"
            #mv -fv "${HF_REPO_LOCAL}/DATA/trickest/." "${SYSTMP}/DATA"
            echo "ARTIFACTS_PATH=${HF_REPO_LOCAL}/DATA/trickest" >> "${GITHUB_ENV}" 2>/dev/null
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
  du -sh "${HF_REPO_LOCAL}/DATA/trickest" && realpath "${HF_REPO_LOCAL}/DATA/trickest"
 fi
}
export -f sync_to_hf
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
 UPSTREAM_HASH="$(curl -qfsSL 'https://huggingface.co/datasets/pkgforge-security/domains/resolve/main/DATA/trickest/hash.txt' 2>/dev/null | tr -d '[:space:]')"
#Sanity Check 
 if [[ "${COMMIT_HASH}" == "${UPSTREAM_HASH}" ]]; then
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
   rm -rf "${HF_REPO_LOCAL}/DATA/trickest" "${TMPDIR}/DATA" 2>/dev/null
   mkdir -p "${HF_REPO_LOCAL}/DATA/trickest" "${TMPDIR}/DATA"
   echo -e "\n[+] Converting CSV ==> JSON (Dasel) ...\n"
   find "${SRC_REPO}" -type f -not -path "*/\.*" -iname '*.csv' -exec bash -c 'cat "$1" 2>/dev/null' _ "{}" \; > "${HF_REPO_LOCAL}/DATA/trickest/cloud.csv"
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
     mv -fv "${TMPDIR}/DATA/cloud.json.tmp" "${HF_REPO_LOCAL}/DATA/trickest/cloud.json"
     mv -fv "${TMPDIR}/DATA/cloud.json.tmp.raw" "${HF_REPO_LOCAL}/DATA/trickest/cloud.jsonl"
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
     sort --version-sort --unique "${TMPDIR}/DATA/cloud.txt" --output "${HF_REPO_LOCAL}/DATA/trickest/cloud.txt"
    #Archive
     if [[ -s "${HF_REPO_LOCAL}/DATA/trickest/cloud.txt" && $(stat -c%s "${HF_REPO_LOCAL}/DATA/trickest/cloud.txt") -gt 1000000 ]]; then
        cp -fv "${HF_REPO_LOCAL}/DATA/trickest/cloud.txt" "${HF_REPO_LOCAL}/DATA/trickest/cloud-${COMMIT_DATE}.txt"
     else
        echo -e "\n[X] FATAL: Failed to Parse Data\n"
        du -sh "${HF_REPO_LOCAL}/DATA/trickest/cloud.txt"
       exit 1
     fi
     if [[ -s "${HF_REPO_LOCAL}/DATA/trickest/cloud.csv" && $(stat -c%s "${HF_REPO_LOCAL}/DATA/trickest/cloud.csv") -gt 1000000 ]]; then
       cp -fv "${HF_REPO_LOCAL}/DATA/trickest/cloud.csv" "${HF_REPO_LOCAL}/DATA/trickest/cloud-${COMMIT_DATE}.csv"
       qsv to sqlite "${HF_REPO_LOCAL}/DATA/trickest/cloud.db" "${HF_REPO_LOCAL}/DATA/trickest/cloud.csv"
       cp -fv "${HF_REPO_LOCAL}/DATA/trickest/cloud.db" "${HF_REPO_LOCAL}/DATA/trickest/cloud-${COMMIT_DATE}.db"
     else
        echo -e "\n[X] FATAL: Failed to Parse CSV Data\n"
        du -sh "${HF_REPO_LOCAL}/DATA/trickest/cloud.csv"
     fi
     if [[ -s "${HF_REPO_LOCAL}/DATA/trickest/cloud.json" && $(stat -c%s "${HF_REPO_LOCAL}/DATA/trickest/cloud.json") -gt 1000000 ]]; then
       cp -fv "${HF_REPO_LOCAL}/DATA/trickest/cloud.json" "${HF_REPO_LOCAL}/DATA/trickest/cloud-${COMMIT_DATE}.json"
       cp -fv "${HF_REPO_LOCAL}/DATA/trickest/cloud.jsonl" "${HF_REPO_LOCAL}/DATA/trickest/cloud-${COMMIT_DATE}.jsonl"
     else
        echo -e "\n[X] FATAL: Failed to Parse JSON Data\n"
        du -sh "${HF_REPO_LOCAL}/DATA/trickest/cloud.json"
     fi
    #Sync
     echo "${COMMIT_HASH}" | tr -d '[:space:]' > "${HF_REPO_LOCAL}/DATA/trickest/hash.txt"
     sync_to_hf
    #Break
     pushd "${TMPDIR}" &>/dev/null
   else
      echo -e "\n[-] FATAL: Failed to get Needed Files\n"
      echo -e "[+] Files : ${T_INPUT[*]}"
     exit 1
   fi
else
  echo -e "\n[X] FATAL: Failed to clone HF Repo\n"
 exit 1
fi
#-------------------------------------------------------#
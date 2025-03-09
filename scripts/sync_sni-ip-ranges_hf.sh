#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Sync sni-ip-ranges ==> HF
## Self: https://raw.githubusercontent.com/pkgforge-security/domains/refs/heads/main/scripts/sync_sni-ip-ranges_hf.sh
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
 if [[ -d "${HF_REPO_LOCAL}/DATA/sni-ip-ranges" ]] && \
  [[ "$(du -s "${HF_REPO_LOCAL}/DATA/sni-ip-ranges" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 100000 ]]; then
  pushd "${HF_REPO_LOCAL}" &>/dev/null &&\
    git remote -v
    COMMIT_MSG="[+] sni-ip-ranges [${I_D}] (${MODTIME})"
    git sparse-checkout set ""
    git sparse-checkout set --no-cone --sparse-index "/README.md"
    git checkout
    git pull origin main
    git pull origin main --ff-only || git pull --rebase origin main
    git merge --no-ff -m "Merge & Sync"
    git fetch origin main
    find "./DATA/sni-ip-ranges" -maxdepth 1 -type f -not -path "*/\.*" -exec basename "{}" \; | xargs -I "{}" git sparse-checkout add "DATA/sni-ip-ranges/{}"
    git lfs track "./DATA/sni-ip-ranges/**"
    git sparse-checkout list 2>/dev/null
    git lfs untrack '.gitattributes' 2>/dev/null
    sed '/\*/!d' -i '.gitattributes'
    find "./DATA/sni-ip-ranges" -maxdepth 1 -type f -not -path "*/\.*" | xargs -I "{}" git add "{}" --verbose
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
            echo -e "\n[+] Pushed ==> [https://huggingface.co/datasets/pkgforge-security/domains/tree/main/DATA/sni-ip-ranges/${I_D}]\n"
            cp -rfv "${HF_REPO_LOCAL}/DATA/sni-ip-ranges/." "${SYSTMP}/DATA"
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
  du -sh "${HF_REPO_LOCAL}/DATA/sni-ip-ranges" && realpath "${HF_REPO_LOCAL}/DATA/sni-ip-ranges"
 fi
}
export -f sync_to_hf
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
        if [[ -s "${TMPDIR}/${I_D}.txt" && $(stat -c%s "${TMPDIR}/${I_D}.txt") -gt 1000 ]]; then
           du -sh "${TMPDIR}/${I_D}.txt"
           #Get modtime
            MODTIME="$(curl -A "${USER_AGENT}" -qfksSL "http://kaeferjaeger.gay/?dir=sni-ip-ranges/${I_D}" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}' | sed -E 's/[[:space:]]+/_/; s/:/-/g' | tr -d '[:space:]')"
            if [[ -z "${MODTIME+x}" ]] || [[ "$(printf '%s' "${MODTIME}" | wc -c)" -lt 10 ]]; then
               MODTIME_TEMP="$(date --utc +%Y-%m-%d_T%H-%M-%S)"
               MODTIME="$(echo "${MODTIME_TEMP}" | sed 's/ZZ\+/Z/Ig' | tr -d '[:space:]')"
            fi
            export MODTIME
           #Copy
             rm -rf "${HF_REPO_LOCAL}/DATA/sni-ip-ranges" 2>/dev/null
             mkdir -p "${HF_REPO_LOCAL}/DATA/sni-ip-ranges"
             cp -fv "${TMPDIR}/${I_D}.txt" "${HF_REPO_LOCAL}/DATA/sni-ip-ranges/${I_D}.txt"
             cp -fv "${TMPDIR}/${I_D}.txt" "${HF_REPO_LOCAL}/DATA/sni-ip-ranges/${I_D}-${MODTIME}.txt"
           #Upload
             sync_to_hf
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
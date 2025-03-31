#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Self: https://raw.githubusercontent.com/pkgforge-security/domains/refs/heads/main/scripts/bb-crt_ghcr_hf.sh
#-------------------------------------------------------#

#-------------------------------------------------------#
##Sanity
if ! command -v anew-rs &> /dev/null; then
  echo -e "[-] Failed to find anew-rs\n"
 exit 1
fi
sudo curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)-$(uname -s)/crt" -o "/usr/local/bin/crt" &&\
sudo chmod 'a+x' -v "/usr/local/bin/crt"
if ! command -v crt &> /dev/null; then
  echo -e "[-] Failed to find crt\n"
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
if command -v python3 >/dev/null && ! command -v python >/dev/null; then
  sudo ln -fsv "$(realpath $(command -v python3))" "/usr/local/bin/python"
elif ! command -v python >/dev/null && ! command -v python3 >/dev/null; then
  exit 1
fi
if ! command -v ripgrep &> /dev/null; then
  echo -e "[-] Failed to find ripgrep\n"
 exit 1
fi
sudo curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)-$(uname -s)/scopegen" -o "/usr/local/bin/scopegen" &&\
sudo chmod 'a+x' -v "/usr/local/bin/scopegen"
if ! command -v scopegen &> /dev/null; then
  echo -e "[-] Failed to find scopegen\n"
 exit 1
fi
sudo curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)-$(uname -s)/subxtract" -o "/usr/local/bin/subxtract" &&\
sudo chmod 'a+x' -v "/usr/local/bin/subxtract"
if ! command -v subxtract &> /dev/null; then
  echo -e "[-] Failed to find subxtract\n"
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
##Oras
 GHCRPKG_URL="ghcr.io/pkgforge-security/domains/bb"
 PKG_WEBPAGE="$(echo "https://github.com/pkgforge-security/domains" | sed 's|^/*||; s|/*$||' | tr -d '[:space:]')"
 export GHCRPKG_URL PKG_WEBPAGE
##Repo
pushd "$(mktemp -d)" &>/dev/null && git clone --filter="blob:none" --depth="1" --no-checkout "https://huggingface.co/datasets/pkgforge-security/domains" && cd "./domains"
 export HF_BRANCH="bb"
 git sparse-checkout set ""
 git sparse-checkout set --no-cone --sparse-index "/README.md"
 git checkout -b "${HF_BRANCH}" || git checkout "${HF_BRANCH}"
 git checkout ; unset HF_REPO_LOCAL ; HF_REPO_LOCAL="$(realpath .)" && export HF_REPO_LOCAL="${HF_REPO_LOCAL}"
 if [ ! -d "${HF_REPO_LOCAL}" ] || [ "$(du -s "${HF_REPO_LOCAL}" | cut -f1 | tr -d '[:space:]')" -le 100 ]; then
   echo -e "\n[X] FATAL: Failed to clone HF Repo\n"
  exit 1
 else
   git lfs install &>/dev/null ; huggingface-cli lfs-enable-largefiles "." &>/dev/null
   #Setup Branch
    setup_hf_branch()
    {
     HF_BRANCH_ESC="$(echo "${HF_BRANCH}" | tr -d '[:space:]' | sed 's/[^a-zA-Z0-9]/_/g' | tr -d '[:space:]')"
     HF_BRANCH_URI="$(echo "${HF_BRANCH}" | tr -d '[:space:]' | jq -sRr '@uri' | tr -d '[:space:]')"
     echo -e "[+] Remote (Branch): ${HF_BRANCH}"
     echo -e "[+] Remote (URL): https://huggingface.co/datasets/pkgforge-security/domains/${HF_BRANCH_URI}"
     git -C "${HF_REPO_LOCAL}" checkout -b "${HF_BRANCH}" || git checkout "${HF_BRANCH}"
     if [[ "$(git -C "${HF_REPO_LOCAL}" rev-parse --abbrev-ref HEAD | sed -e '/^[[:space:]]*$/d;1q' | tr -d '[:space:]')" != "${HF_BRANCH}" ]]; then
        echo -e "\n[-] FATAL: Failed to switch to ${HF_BRANCH}\n"
       return 1
     else
       git -C "${HF_REPO_LOCAL}" fetch origin "${HF_BRANCH}" 2>/dev/null
       #echo HF_BRANCH="${HF_BRANCH}" >> "${GITHUB_ENV}"
       #echo HF_BRANCH_ESC="${HF_BRANCH_ESC}" >> "${GITHUB_ENV}"
       #echo HF_BRANCH_URI="${HF_BRANCH_URI}" >> "${GITHUB_ENV}"
     fi
    }
    export -f setup_hf_branch
 fi
popd &>/dev/null
#-------------------------------------------------------#

#-------------------------------------------------------#
##Func
sync_to_ghcr()
{
 if [[ -d "${HF_REPO_LOCAL}/DATA" ]] && \
  [[ "$(du -s "${HF_REPO_LOCAL}/DATA" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 1000 ]]; then
  pushd "${HF_REPO_LOCAL}" &>/dev/null &&\
   unset GHCRPKG_TAG MODTIME_TEMP
   MODTIME="$(date --utc '+%Y-%m-%d_T%H-%M-%S' | sed 's/ZZ\+/Z/Ig' | tr -d '[:space:]')"
   GHCRPKG_TAG="$(echo "bb-crt-${MODTIME}" | sed 's/[^a-zA-Z0-9._-]/_/g; s/_*$//')"
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
        ghcr_push+=(--annotation "org.opencontainers.image.description=bb-data-crt-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.documentation=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.licenses=blessing")
        ghcr_push+=(--annotation "org.opencontainers.image.ref.name=crt-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.revision=crt-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.source=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.title=bb-crt-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.url=${SRC_URL}")
        ghcr_push+=(--annotation "org.opencontainers.image.vendor=pkgforge-security")
        ghcr_push+=(--annotation "org.opencontainers.image.version=crt-${MODTIME}")
        ghcr_push+=("${GHCRPKG_URL}:${GHCRPKG_TAG},latest")
        pushd "${HF_REPO_LOCAL}/DATA" &>/dev/null
        oras_files=() ; mapfile -t oras_files < <(find "." -type f -not -path "*/\.*" -print 2>/dev/null)
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
  du -sh "${HF_REPO_LOCAL}/DATA" && realpath "${HF_REPO_LOCAL}/DATA"
 fi
}
export -f sync_to_ghcr
#-------------------------------------------------------#

#-------------------------------------------------------#
##Func
sync_to_hf() 
{
 if [[ -d "${HF_REPO_LOCAL}/DATA" ]] && \
  [[ "$(du -s "${HF_REPO_LOCAL}/DATA" | cut -f1 | tr -cd '0-9' | tr -d '[:space:]')" -gt 1000 ]]; then
  pushd "${HF_REPO_LOCAL}" &>/dev/null &&\
    setup_hf_branch
    git remote -v
    COMMIT_MSG="[+] bb [CRT List]"
    git sparse-checkout set ""
    git sparse-checkout set --no-cone --sparse-index "/README.md"
    git checkout -b "${HF_BRANCH}" || git checkout "${HF_BRANCH}"
    git pull origin "${HF_BRANCH}"
    git pull origin "${HF_BRANCH}" --ff-only || git pull --rebase origin "${HF_BRANCH}"
    git merge --no-ff -m "Merge & Sync"
    git fetch origin "${HF_BRANCH}"
    git sparse-checkout add "**"
    git sparse-checkout list
    pushd "${HF_REPO_LOCAL}" &&\
    git lfs track "./DATA/**"
    git sparse-checkout list 2>/dev/null
    git lfs untrack '.gitattributes' 2>/dev/null
    sed '/\*/!d' -i '.gitattributes'
    find "./DATA" -type f -not -path "*/\.*" | xargs -I "{}" git add "{}" --verbose
    git add --all --renormalize --verbose
    git commit -m "${COMMIT_MSG}"
    pushd "${HF_REPO_LOCAL}" &>/dev/null
     retry_git_push()
      {
       for i in {1..5}; do
        #Generic Merge
         git pull origin "${HF_BRANCH}" --ff-only || git pull --rebase origin "${HF_BRANCH}"
         git merge --no-ff -m "${COMMIT_MSG}"
        #Push
         git pull origin "${HF_BRANCH}" 2>/dev/null
         if git push -u origin "${HF_BRANCH}"; then
            echo -e "\n[+] Pushed ==> [https://huggingface.co/datasets/pkgforge-security/domains/tree/${HF_BRANCH}/DATA/]\n"
            echo "GEN_CRT=YES" >> "${GITHUB_ENV}" 2>/dev/null
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
       echo -e "\n[-] WARN: Failed to push ==> [Latest List]\n(Retrying ...)\n"
       retry_git_push
       git --no-pager log '-1' --pretty="format:'%h - %ar - %s - %an'"
       if ! git ls-remote --heads origin | grep -qi "$(git rev-parse HEAD)"; then
         echo -e "\n[-] FATAL: Failed to push ==> [Latest List]\n"
         echo "GEN_CRT=NO" >> "${GITHUB_ENV}" 2>/dev/null
         rm -rf "${HF_REPO_LOCAL}/.git" 2>/dev/null
         echo -e "\n[+] Trying with HuggingFace CLI ...\n"
         huggingface-cli upload "pkgforge-security/domains" "${HF_REPO_LOCAL}" --repo-type "dataset" --revision "${HF_BRANCH}" --commit-message "${COMMIT_MSG}"
       fi
      fi
  du -sh "${HF_REPO_LOCAL}/DATA" && realpath "${HF_REPO_LOCAL}/DATA"
 fi
}
export -f sync_to_hf
#-------------------------------------------------------#

#-------------------------------------------------------#
cleanup_domains()
{
 set -x ; echo -e "\n"
 [[ -s "$1" ]] || return 1
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
 echo -e "\n" && time sort -u "$1" -o "$1"
 wc -l "$1"
 set +x ; echo -e "\n"
}
export -f cleanup_domains
#-------------------------------------------------------#

#-------------------------------------------------------#
##Fetch CRT
#https://huggingface.co/datasets/pkgforge-security/domains/tree/bb/DATA
pushd "${TMPDIR}" &>/dev/null
  curl -qfsSL "https://huggingface.co/datasets/pkgforge-security/domains/resolve/bb/DATA/ct/latest.txt" -o "${TMPDIR}/ct-input.txt"
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' -i "${TMPDIR}/ct-input.txt"
  if [[ "$(wc -l < "${TMPDIR}/ct-input.txt" | tr -cd '0-9')" -le 1000 ]]; then
     echo -e "[-] Failed to Fetch Crt Input\n"
    exit 1
  else
     DST_DIR="${HF_REPO_LOCAL}/DATA/ct"
     DST_FILE="${DST_DIR}/latest.ct.json"
     DST_FILE_L="${DST_DIR}/latest.ct.jsonl"
     DST_FILE_R="${DST_DIR}/latest.ct.raw.jsonl"
     rm -rf "${DST_DIR}" 2>/dev/null
     mkdir -p "${DST_DIR}"
     timeout -k 1m 69m crt -i "${TMPDIR}/ct-input.txt" -c "${PARALLEL_LIMIT:-100}" -d "${DELAY_LIMIT:-500}" -l "${RESULT_LIMIT:-4}" -jsonl -o "${TMPDIR}/latest.ct.raw.jsonl" &>/dev/null
       echo -e "\n[+] Processing Generated ${DST_FILE_R}\n"
       #L_N="0"
       #T_N="$(wc -l < "${DST_FILE_R}" | tr -cd '0-9')"
       #echo "" > "${TMPDIR}/latest.ct.jsonl"
       #mapfile -t "J_LINES" < "${DST_FILE_R}"
       #for LINE in "${J_LINES[@]}"; do
       #  L_N="$((L_N + 1))"
       #  if echo "${LINE}" | jq -c . >/dev/null 2>&1; then
       #      echo "%s\n" "${LINE}" >> "${TMPDIR}/latest.ct.jsonl"
       #      echo "Processed line: ${L_N}/${T_N}"
       #  else
       #      echo "Skipped invalid JSON at line: ${L_N}"
       #  fi
       #done
       #cp -fv "${TMPDIR}/latest.ct.jsonl" "${DST_FILE_R}"
       cat "${TMPDIR}/latest.ct.raw.jsonl" | jq . > "${TMPDIR}/latest.ct.jsonl" 2>/dev/null
       if [[ -s "${TMPDIR}/latest.ct.raw.jsonl" && $(stat -c%s "${TMPDIR}/latest.ct.raw.jsonl") -gt 10000 ]]; then
         jq -s 'if type == "array" then . else [.] end' "${TMPDIR}/latest.ct.raw.jsonl" > "${TMPDIR}/latest.ct.json"
         if [[ "$(jq -r '.[] | .common_name' "${TMPDIR}/latest.ct.json" | grep -iv 'null' | wc -l | tr -cd '0-9')" -ge 20 ]]; then
            cp -fv "${TMPDIR}/latest.ct.jsonl" "${DST_FILE_L}"
            cp -fv "${TMPDIR}/latest.ct.raw.jsonl" "${DST_FILE_R}"
            cp -fv "${TMPDIR}/latest.ct.json" "${DST_FILE}"
         else
            echo "" > "${DST_FILE}"
            echo "" > "${DST_FILE_L}"
            echo "" > "${DST_FILE_R}"
         fi
       else
         echo "" > "${DST_FILE}"
         echo "" > "${DST_FILE_L}"
         echo "" > "${DST_FILE_R}"
       fi
  fi
#-------------------------------------------------------#
  
#-------------------------------------------------------#
#Parse CRT
pushd "${TMPDIR}" &>/dev/null
 unset DST_DIR DST_FILE DST_FILE_D DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
 DST_DIR="${HF_REPO_LOCAL}/DATA/ct"
 DST_FILE="${DST_DIR}/latest.ct.txt"
 DST_FILE_D="${DST_DIR}/latest.nrd.txt"
 DST_FILE_N="${DST_DIR}/latest.ct_nrd.txt"
 SRC_FILE="${DST_DIR}/latest.ct.json"
 if [[ "$(jq -r '.[] | .common_name' "${SRC_FILE}" | grep -iv 'null' | wc -l | tr -cd '0-9')" -ge 20 ]]; then
    cat "${SRC_FILE}" |\
     jq -r '.[] | "ID: \(.issuer_ca_id)\nName: \(.common_name)\nEntry: \(.entry_timestamp)\nIssued: \(.not_before)\nExpiry: \(.not_after)\n------------"' > "${DST_FILE}"
     sed '$s/--*$//' -i "${DST_FILE}"
     sed '/^$/d' -i "${DST_FILE}"
    cat "${SRC_FILE}" | jq -r '.[] | select(.nrd == "likely") | .common_name' > "${DST_FILE_D}"
    cat "${SRC_FILE}" | jq -r '.[] | select(.nrd == "likely") | .name_value' >> "${DST_FILE_D}"
     cleanup_domains "${DST_FILE_D}"
    cat "${SRC_FILE}" |\
     jq -r '.[] | select(.nrd == "likely") | "ID: \(.issuer_ca_id)\nName: \(.common_name)\nEntry: \(.entry_timestamp)\nIssued: \(.not_before)\nExpiry: \(.not_after)\n------------"' > "${DST_FILE_N}"
     sed '$s/--*$//' -i "${DST_FILE_N}"
     sed '/^$/d' -i "${DST_FILE_N}"
 else
    echo "" > "${DST_FILE}"
    echo "" > "${DST_FILE_L}"
    echo "" > "${DST_FILE_R}"
 fi
#-------------------------------------------------------#

#-------------------------------------------------------#
#Upload
pushd "${TMPDIR}" &>/dev/null
 find "${HF_REPO_LOCAL}/DATA/" -type f -size -3c -print -delete \; 2>/dev/null
 tree "${HF_REPO_LOCAL}/DATA" || find "${HF_REPO_LOCAL}/DATA" | sort | awk -F/ '{indent=""; for (i=2; i<NF; i++) indent=indent " "; print (NF>1 ? indent "--> " $NF : $NF)}' ; echo -e "\n"
 realpath "${HF_REPO_LOCAL}/DATA/ct" && ls -sh "${HF_REPO_LOCAL}/DATA/ct" ; echo -e "\n"
 echo "ARTIFACTS_PATH=${HF_REPO_LOCAL}/DATA" >> "${GITHUB_ENV}" 2>/dev/null
 sync_to_ghcr
 sync_to_hf
popd &>/dev/null
#-------------------------------------------------------#
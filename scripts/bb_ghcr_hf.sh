#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Self: https://raw.githubusercontent.com/pkgforge-security/domains/refs/heads/main/scripts/bb_ghcr_hf.sh
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
if ! command -v ripgrep &> /dev/null; then
  echo -e "[-] Failed to find ripgrep\n"
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
   GHCRPKG_TAG="$(echo "bb-${MODTIME}" | sed 's/[^a-zA-Z0-9._-]/_/g; s/_*$//')"
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
        ghcr_push+=(--annotation "org.opencontainers.image.description=bb-data-latest-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.documentation=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.licenses=blessing")
        ghcr_push+=(--annotation "org.opencontainers.image.ref.name=latest-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.revision=latest-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.source=${PKG_WEBPAGE}")
        ghcr_push+=(--annotation "org.opencontainers.image.title=bb-latest-${MODTIME}")
        ghcr_push+=(--annotation "org.opencontainers.image.url=${SRC_URL}")
        ghcr_push+=(--annotation "org.opencontainers.image.vendor=pkgforge-security")
        ghcr_push+=(--annotation "org.opencontainers.image.version=latest-${MODTIME}")
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
    COMMIT_MSG="[+] bb [Latest List]"
    git sparse-checkout set ""
    git sparse-checkout set --no-cone --sparse-index "/README.md"
    git checkout -b "${HF_BRANCH}" || git checkout "${HF_BRANCH}"
    git pull origin "${HF_BRANCH}"
    git pull origin "${HF_BRANCH}" --ff-only || git pull --rebase origin "${HF_BRANCH}"
    git merge --no-ff -m "Merge & Sync"
    git fetch origin "${HF_BRANCH}"
    git sparse-checkout add "**"
    git sparse-checkout list
    find "./DATA" -type f -not -path "*/\.*" -exec basename "{}" \; | xargs -I "{}" add "DATA/{}"
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
         retry_git_push
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
 echo -e "\n" ; ripgrep "$1" --color="never" --engine="auto" --file="${TMPDIR}/psl.re" --ignore-case --no-line-number --only-matching | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "$1.tmp" && mv -fv "$1.tmp" "$1"
 echo -e "\n" && time sed 's/^[[:space:]]*//;s/[[:space:]]*$//' -i "$1" ; du -sh "$1"
 echo -e "\n" && time sort -u "$1" -o "$1"
 wc -l "$1"
 set +x ; echo -e "\n"
}
export -f cleanup_domains
#-------------------------------------------------------#

#-------------------------------------------------------#
##SRC//DEST
#https://huggingface.co/datasets/pkgforge-security/domains/tree/bb/DATA
pushd "${TMPDIR}" &>/dev/null
  curl -qfsSL "https://raw.githubusercontent.com/pkgforge-security/domains/refs/heads/main/psl/psl.re.len.rev" -o "${TMPDIR}/psl.re"
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' -i "${TMPDIR}/psl.re"
  if [[ "$(wc -l < "${TMPDIR}/psl.re" | tr -cd '0-9')" -le 1000 ]]; then
     echo -e "[-] Failed to Fetch Public Suffix List\n"
    exit 1
  fi
  rm -rf "${HF_REPO_LOCAL}/DATA" 2>/dev/null
  mkdir -p "${HF_REPO_LOCAL}/DATA"
  fetch_src()
  {
    mkdir -p "${DST_DIR}"
    find "${DST_DIR}" -type f -iname "*$(basename "${DST_FILE%.*}")*" -exec rm -rvf "{}" 2>/dev/null \;
    curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "${SRC_URL}" --retry 3 --retry-all-errors -o "${TMPDIR}/${DST_FILE_N}"
    if [[ -s "${TMPDIR}/${DST_FILE_N}" && $(stat -c%s "${TMPDIR}/${DST_FILE_N}") -gt 1000 ]]; then
      cp -fv "${TMPDIR}/${DST_FILE_N}" "${DST_FILE_R}"
      #ripgrep "${TMPDIR}/${DST_FILE_N}" --color="never" --engine="auto" --file="${TMPDIR}/psl.re" --ignore-case --no-line-number --only-matching | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "${DST_FILE}"
      cp -fv "${TMPDIR}/${DST_FILE_N}" "${DST_FILE}"
      sort -u "${DST_FILE}" -o "${DST_FILE}" ; wc -l "${DST_FILE}"
      sort -u "${DST_FILE_R}" -o "${DST_FILE_R}" ; wc -l "${DST_FILE_R}"
    fi
  }
  export -f fetch_src
 #https://github.com/rix4uni/scope [BugCrowd] (InScope)
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/rix4uni-bugcrowd_inscope.txt"
   DST_DIR="${HF_REPO_LOCAL}/DATA/rix4uni"
   DST_FILE="${DST_DIR}/bugcrowd_inscope.txt"
   DST_FILE_N="rix4uni-bugcrowd_inscope.txt"
   DST_FILE_R="${DST_DIR}/bugcrowd_inscope.raw.txt"
   SRC_URL="https://raw.githubusercontent.com/rix4uni/scope/refs/heads/main/data/Bugcrowd/bugcrowd_inscope.txt"
   fetch_src && cleanup_domains "${DST_FILE}"
 #https://github.com/rix4uni/scope [BugCrowd] (OutScope)
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/rix4uni-bugcrowd_outofscope.txt"
   DST_DIR="${HF_REPO_LOCAL}/DATA/rix4uni"
   DST_FILE="${DST_DIR}/bugcrowd_outofscope.txt"
   DST_FILE_N="rix4uni-bugcrowd_outofscope.txt"
   DST_FILE_R="${DST_DIR}/bugcrowd_outofscope.raw.txt"
   SRC_URL="https://raw.githubusercontent.com/rix4uni/scope/refs/heads/main/data/Bugcrowd/bugcrowd_outofscope.txt"
   fetch_src && cleanup_domains "${DST_FILE}"
 #https://github.com/rix4uni/scope [HackerOne] (InScope)
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/rix4uni-hackerone_inscope.txt"
   DST_DIR="${HF_REPO_LOCAL}/DATA/rix4uni"
   DST_FILE="${DST_DIR}/hackerone_inscope.txt"
   DST_FILE_N="rix4uni-hackerone_inscope.txt"
   DST_FILE_R="${DST_DIR}/hackerone_inscope.raw.txt"
   SRC_URL="https://raw.githubusercontent.com/rix4uni/scope/refs/heads/main/data/Hackerone/hackerone_inscope.txt"
   fetch_src && cleanup_domains "${DST_FILE}"
 #https://github.com/rix4uni/scope [HackerOne] (OutScope)
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/rix4uni-hackerone_outofscope.txt"
   DST_DIR="${HF_REPO_LOCAL}/DATA/rix4uni"
   DST_FILE="${DST_DIR}/hackerone_outofscope.txt"
   DST_FILE_N="rix4uni-hackerone_outofscope.txt"
   DST_FILE_R="${DST_DIR}/hackerone_outofscope.raw.txt"
   SRC_URL="https://raw.githubusercontent.com/rix4uni/scope/refs/heads/main/data/Hackerone/hackerone_outofscope.txt"
   fetch_src && cleanup_domains "${DST_FILE}"
 #https://github.com/rix4uni/scope [IntiGriti] (InScope)
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/rix4uni-intigriti_inscope.txt"
   DST_DIR="${HF_REPO_LOCAL}/DATA/rix4uni"
   DST_FILE="${DST_DIR}/intigriti_inscope.txt"
   DST_FILE_N="rix4uni-intigriti_inscope.txt"
   DST_FILE_R="${DST_DIR}/intigriti_inscope.raw.txt"
   SRC_URL="https://raw.githubusercontent.com/rix4uni/scope/refs/heads/main/data/Intigriti/intigriti_inscope.txt"
   fetch_src && cleanup_domains "${DST_FILE}"
 #https://github.com/rix4uni/scope [IntiGriti] (OutScope)
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/rix4uni-intigriti_outofscope.txt"
   DST_DIR="${HF_REPO_LOCAL}/DATA/rix4uni"
   DST_FILE="${DST_DIR}/intigriti_outofscope.txt"
   DST_FILE_N="rix4uni-intigriti_outofscope.txt"
   DST_FILE_R="${DST_DIR}/intigriti_outofscope.raw.txt"
   SRC_URL="https://raw.githubusercontent.com/rix4uni/scope/refs/heads/main/data/Intigriti/intigriti_outofscope.txt"
   fetch_src && cleanup_domains "${DST_FILE}"
 #https://github.com/rix4uni/scope [YesWeHack] (InScope)
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/rix4uni-yeswehack_inscope.txt"
   DST_DIR="${HF_REPO_LOCAL}/DATA/rix4uni"
   DST_FILE="${DST_DIR}/yeswehack_inscope.txt"
   DST_FILE_N="rix4uni-yeswehack_inscope.txt"
   DST_FILE_R="${DST_DIR}/yeswehack_inscope.raw.txt"
   SRC_URL="https://raw.githubusercontent.com/rix4uni/scope/refs/heads/main/data/Yeswehack/yeswehack_inscope.txt"
   fetch_src && cleanup_domains "${DST_FILE}"
 #https://github.com/rix4uni/scope [YesWeHack] (OutScope)
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/rix4uni-yeswehack_outofscope.txt"
   DST_DIR="${HF_REPO_LOCAL}/DATA/rix4uni"
   DST_FILE="${DST_DIR}/yeswehack_outofscope.txt"
   DST_FILE_N="rix4uni-yeswehack_outofscope.txt"
   DST_FILE_R="${DST_DIR}/yeswehack_outofscope.raw.txt"
   SRC_URL="https://raw.githubusercontent.com/rix4uni/scope/refs/heads/main/data/Yeswehack/yeswehack_outofscope.txt"
   fetch_src && cleanup_domains "${DST_FILE}"
 #https://github.com/rix4uni/scope [Latest] (InScope)
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/rix4uni-inscope_domains.txt"
   DST_DIR="${HF_REPO_LOCAL}/DATA/rix4uni"
   DST_FILE="${DST_DIR}/inscope_domains.txt"
   DST_FILE_N="rix4uni-inscope_domains.txt"
   DST_FILE_R="${DST_DIR}/inscope_domains.raw.txt"
   SRC_URL="https://raw.githubusercontent.com/rix4uni/scope/refs/heads/main/data/Domains/inscope_domains.txt"
   fetch_src && cleanup_domains "${DST_FILE}"
 #https://github.com/rix4uni/scope [Latest] (OutScope)
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/rix4uni-outofscope_domains.txt"
   DST_DIR="${HF_REPO_LOCAL}/DATA/rix4uni"
   DST_FILE="${DST_DIR}/outofscope_domains.txt"
   DST_FILE_N="rix4uni-outofscope_domains.txt"
   DST_FILE_R="${DST_DIR}/outofscope_domains.raw.txt"
   SRC_URL="https://raw.githubusercontent.com/rix4uni/scope/refs/heads/main/data/Domains/outofscope_domains.txt"
   fetch_src && cleanup_domains "${DST_FILE}"
 #https://github.com/rix4uni/scope [WildCard] (InScope)
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/rix4uni-inscope_wildcards.txt"
   DST_DIR="${HF_REPO_LOCAL}/DATA/rix4uni"
   DST_FILE="${DST_DIR}/inscope_wildcards.txt"
   DST_FILE_N="rix4uni-inscope_wildcards.txt"
   DST_FILE_R="${DST_DIR}/inscope_wildcards.raw.txt"
   SRC_URL="https://raw.githubusercontent.com/rix4uni/scope/refs/heads/main/data/Wildcards/inscope_wildcards.txt"
   fetch_src && cleanup_domains "${DST_FILE}"
 #https://github.com/rix4uni/scope [WildCard] (OutScope)
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/rix4uni-outofscope_wildcards.txt"
   DST_DIR="${HF_REPO_LOCAL}/DATA/rix4uni"
   DST_FILE="${DST_DIR}/outofscope_wildcards.txt"
   DST_FILE_N="rix4uni-outofscope_wildcards.txt"
   DST_FILE_R="${DST_DIR}/outofscope_wildcards.raw.txt"
   SRC_URL="https://raw.githubusercontent.com/rix4uni/scope/refs/heads/main/data/Wildcards/outofscope_wildcards.txt"
   fetch_src && cleanup_domains "${DST_FILE}"
 #https://github.com/arkadiyt/bounty-targets-data [BugCrowd]
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/arkadiyt-bugcrowd.json"
   DST_DIR="${HF_REPO_LOCAL}/DATA/arkadiyt"
   DST_FILE="${DST_DIR}/bugcrowd.json"
   DST_FILE_N="arkadiyt-bugcrowd.json"
   DST_FILE_R="${DST_DIR}/bugcrowd.raw.json"
   SRC_URL="https://raw.githubusercontent.com/arkadiyt/bounty-targets-data/refs/heads/main/data/bugcrowd_data.json"
    mkdir -p "${DST_DIR}" ; find "${DST_DIR}" -type f -iname "*bugcrowd*" -exec rm -rvf "{}" 2>/dev/null \;
    curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "${SRC_URL}" --retry 3 --retry-all-errors -o "${TMPDIR}/${DST_FILE_N}"
    if [[ -s "${TMPDIR}/${DST_FILE_N}" && $(stat -c%s "${TMPDIR}/${DST_FILE_N}") -gt 1000 ]]; then
      cat "${TMPDIR}/${DST_FILE_N}" | jq . > "${DST_FILE}"
      cp -fv "${TMPDIR}/${DST_FILE_N}" "${DST_FILE_R}"
      #ALL:Programs [Scope:ALL] [Type:Public] [ALL]
       cat "${DST_FILE}" | jq -r '.[] | .. | select(type == "object") | .target // ""' |\
       grep -E '^\s*[a-zA-Z0-9]' | sed 's/^\s*//; s/\s*$//' | sed 's/[A-Z]/\L&/g' | sort -u -o "${DST_DIR}/bugcrowd.raw.txt"
       cat "${DST_DIR}/bugcrowd.raw.txt" |\
       tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/bugcrowd_all_domains.txt"
       cleanup_domains "${DST_DIR}/bugcrowd_all_domains.txt"
       sort -u "${DST_DIR}/bugcrowd_all_domains.txt" -o "${DST_DIR}/bugcrowd_all_domains.txt"
      #ALL:Programs [Scope:Inscope] [Type:Public] [ALL]
       cat "${DST_FILE}" | jq -r '.[] | select(.targets?.in_scope?) | .targets.in_scope[] | .target // ""' |\
       grep -E '^\s*[a-zA-Z0-9]' | sed 's/^\s*//; s/\s*$//' | sed 's/[A-Z]/\L&/g' | sort -u -o "${DST_DIR}/bugcrowd_inscope.raw.txt"
       cat "${DST_DIR}/bugcrowd_inscope.raw.txt" | tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep "*." | grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/bugcrowd_inscope_wildcards.txt"
       cat "${DST_DIR}/bugcrowd_inscope.raw.txt" |\
       tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/bugcrowd_all_domains_inscope.txt"
       cleanup_domains "${DST_DIR}/bugcrowd_all_domains_inscope.txt"
       sort -u "${DST_DIR}/bugcrowd_all_domains_inscope.txt" -o "${DST_DIR}/bugcrowd_all_domains_inscope.txt"
      #ALL:Programs [Scope:ALL] [Type:Public] [BBP]
       cat "${DST_FILE}" | jq -r '.[] | select(.max_payout > 0) | .. | select(type == "object") | .target // ""' |\
       tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/bugcrowd_all_domains_bbp.txt"
       cleanup_domains "${DST_DIR}/bugcrowd_all_domains_bbp.txt"
       sort -u "${DST_DIR}/bugcrowd_all_domains_bbp.txt" -o "${DST_DIR}/bugcrowd_all_domains_bbp.txt"
      #ALL:Programs [Scope:ALL] [Type:Public] [VDP]
       cat "${DST_FILE}" | jq -r '.[] | select(.max_payout == null or .max_payout <= 0) | .. | select(type == "object") | .target // ""' |\
       tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/bugcrowd_all_domains_vdp.txt"
       cleanup_domains "${DST_DIR}/bugcrowd_all_domains_vdp.txt"
       sort -u "${DST_DIR}/bugcrowd_all_domains_vdp.txt" -o "${DST_DIR}/bugcrowd_all_domains_vdp.txt"
    fi
 #https://github.com/arkadiyt/bounty-targets-data [Hackerone]
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/arkadiyt-hackerone.json"
   DST_DIR="${HF_REPO_LOCAL}/DATA/arkadiyt"
   DST_FILE="${DST_DIR}/hackerone.json"
   DST_FILE_N="arkadiyt-hackerone.json"
   DST_FILE_R="${DST_DIR}/hackerone.raw.json"
   SRC_URL="https://raw.githubusercontent.com/arkadiyt/bounty-targets-data/refs/heads/main/data/hackerone_data.json"
    mkdir -p "${DST_DIR}" ; find "${DST_DIR}" -type f -iname "*hackerone*" -exec rm -rvf "{}" 2>/dev/null \;
    curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "${SRC_URL}" --retry 3 --retry-all-errors -o "${TMPDIR}/${DST_FILE_N}"
    if [[ -s "${TMPDIR}/${DST_FILE_N}" && $(stat -c%s "${TMPDIR}/${DST_FILE_N}") -gt 1000 ]]; then
      cat "${TMPDIR}/${DST_FILE_N}" | jq . > "${DST_FILE}"
      cp -fv "${TMPDIR}/${DST_FILE_N}" "${DST_FILE_R}"
      #ALL:Programs [Scope:ALL] [Type:Public] [ALL]
       cat "${DST_FILE}" | jq -r '.. | select(.asset_identifier?) | .asset_identifier' |\
       grep -E '^\s*[a-zA-Z0-9]' | sed 's/^\s*//; s/\s*$//' | sed 's/[A-Z]/\L&/g' | sort -u -o "${DST_DIR}/hackerone.raw.txt"
       cat "${DST_DIR}/hackerone.raw.txt" |\
       tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/hackerone_all_domains.txt"
       cleanup_domains "${DST_DIR}/hackerone_all_domains.txt"
       sort -u "${DST_DIR}/hackerone_all_domains.txt" -o "${DST_DIR}/hackerone_all_domains.txt"
      #ALL:Programs [Scope:Inscope] [Type:Public] [ALL]
       cat "${DST_FILE}" | jq -r '.[] | select(.targets?.in_scope?) | .targets.in_scope[] | .asset_identifier // ""' |\
       grep -E '^\s*[a-zA-Z0-9]' | sed 's/^\s*//; s/\s*$//' | sed 's/[A-Z]/\L&/g' | sort -u -o "${DST_DIR}/hackerone_inscope.raw.txt"
       cat "${DST_DIR}/hackerone_inscope.raw.txt" | tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep "*." | grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/hackerone_inscope_wildcards.txt"
       cat "${DST_DIR}/hackerone_inscope.raw.txt" |\
       tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/hackerone_all_domains_inscope.txt"
       cleanup_domains "${DST_DIR}/hackerone_all_domains_inscope.txt"
       sort -u "${DST_DIR}/hackerone_all_domains_inscope.txt" -o "${DST_DIR}/hackerone_all_domains_inscope.txt"
      #ALL:Programs [Scope:ALL] [Type:Public] [BBP]
       cat "${DST_FILE}" | jq -r '.. | select(.eligible_for_bounty? == true) | .asset_identifier? // ""' |\
       tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/hackerone_all_domains_bbp.txt"
       cleanup_domains "${DST_DIR}/hackerone_all_domains_bbp.txt"
       sort -u "${DST_DIR}/hackerone_all_domains_bbp.txt" -o "${DST_DIR}/hackerone_all_domains_bbp.txt"
      #ALL:Programs [Scope:ALL] [Type:Public] [VDP]
       cat "${DST_FILE}" | jq -r '.. | select(.eligible_for_bounty? == false) | .asset_identifier? // ""' |\
       tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/hackerone_all_domains_vdp.txt"
       cleanup_domains "${DST_DIR}/hackerone_all_domains_vdp.txt"
       sort -u "${DST_DIR}/hackerone_all_domains_vdp.txt" -o "${DST_DIR}/hackerone_all_domains_vdp.txt"
    fi
 #https://github.com/arkadiyt/bounty-targets-data [IntiGriti]
   unset DST_DIR DST_FILE DST_FILE_N DST_FILE_R SRC_FILE SRC_URL
   SRC_FILE="${TMPDIR}/arkadiyt-intigriti.json"
   DST_DIR="${HF_REPO_LOCAL}/DATA/arkadiyt"
   DST_FILE="${DST_DIR}/intigriti.json"
   DST_FILE_N="arkadiyt-intigriti.json"
   DST_FILE_R="${DST_DIR}/intigriti.raw.json"
   SRC_URL="https://raw.githubusercontent.com/arkadiyt/bounty-targets-data/refs/heads/main/data/intigriti_data.json"
    mkdir -p "${DST_DIR}" ; find "${DST_DIR}" -type f -iname "*intigriti*" -exec rm -rvf "{}" 2>/dev/null \;
    curl -A "${USER_AGENT}" -w "(DL) <== %{url}\n" -fSL "${SRC_URL}" --retry 3 --retry-all-errors -o "${TMPDIR}/${DST_FILE_N}"
    if [[ -s "${TMPDIR}/${DST_FILE_N}" && $(stat -c%s "${TMPDIR}/${DST_FILE_N}") -gt 1000 ]]; then
      cat "${TMPDIR}/${DST_FILE_N}" | jq . > "${DST_FILE}"
      cp -fv "${TMPDIR}/${DST_FILE_N}" "${DST_FILE_R}"
      #ALL:Programs [Scope:ALL] [Type:Public] [ALL]
       cat "${DST_FILE}" | jq -r '.. | select(.endpoint?) | .endpoint' |\
       grep -E '^\s*[a-zA-Z0-9]' | sed 's/^\s*//; s/\s*$//' | sed 's/[A-Z]/\L&/g' | sort -u -o "${DST_DIR}/intigriti.raw.txt"
       cat "${DST_DIR}/intigriti.raw.txt" |\
       tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/intigriti_all_domains.txt"
       cleanup_domains "${DST_DIR}/intigriti_all_domains.txt"
       sort -u "${DST_DIR}/intigriti_all_domains.txt" -o "${DST_DIR}/intigriti_all_domains.txt"
      #ALL:Programs [Scope:Inscope] [Type:Public] [ALL]
       cat "${DST_FILE}" | jq -r '.[] | select(.targets.in_scope?) | .targets.in_scope[] | .endpoint // ""' |\
       grep -E '^\s*[a-zA-Z0-9]' | sed 's/^\s*//; s/\s*$//' | sed 's/[A-Z]/\L&/g' | sort -u -o "${DST_DIR}/intigriti_inscope.raw.txt"
       cat "${DST_DIR}/intigriti_inscope.raw.txt" | tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep "*." | grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/intigriti_inscope_wildcards.txt"
       cat "${DST_DIR}/intigriti_inscope.raw.txt" |\
       tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/intigriti_all_domains_inscope.txt"
       cleanup_domains "${DST_DIR}/intigriti_all_domains_inscope.txt"
       sort -u "${DST_DIR}/intigriti_all_domains_inscope.txt" -o "${DST_DIR}/intigriti_all_domains_inscope.txt"
      #ALL:Programs [Scope:ALL] [Type:Public] [BBP]
       cat "${DST_FILE}" | jq -r '.[] | select(.min_bounty.value > 0) | .. | select(type == "object") | .endpoint // ""' |\
       tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/intigriti_all_domains_bbp.txt"
       cleanup_domains "${DST_DIR}/intigriti_all_domains_bbp.txt"
       sort -u "${DST_DIR}/intigriti_all_domains_bbp.txt" -o "${DST_DIR}/intigriti_all_domains_bbp.txt"
      #ALL:Programs [Scope:ALL] [Type:Public] [VDP]
       cat "${DST_FILE}" | jq -r '.[] | select(.min_bounty.value <= 0) | .. | select(type == "object") | .endpoint // ""' |\
       tr "," "\n" | sed 's/http[s]*:\/\/\|www.//g' | sed 's/\s//g' |\
       grep -Eo '[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}' | sort -u -o "${DST_DIR}/intigriti_all_domains_vdp.txt"
       cleanup_domains "${DST_DIR}/intigriti_all_domains_vdp.txt"
       sort -u "${DST_DIR}/intigriti_all_domains_vdp.txt" -o "${DST_DIR}/intigriti_all_domains_vdp.txt"
    fi
  #Cleanup
   find "${HF_REPO_LOCAL}/DATA/" -type f -size -3c -print -delete \; 2>/dev/null
  #List
   tree "${HF_REPO_LOCAL}/DATA" || find "${HF_REPO_LOCAL}/DATA" | sort | awk -F/ '{indent=""; for (i=2; i<NF; i++) indent=indent " "; print (NF>1 ? indent "--> " $NF : $NF)}' ; echo -e "\n"
   realpath "${HF_REPO_LOCAL}/DATA/arkadiyt" && ls -sh "${HF_REPO_LOCAL}/DATA/arkadiyt" ; echo -e "\n"
   realpath "${HF_REPO_LOCAL}/DATA/rix4uni" && ls -sh "${HF_REPO_LOCAL}/DATA/rix4uni" ; echo -e "\n"
#-------------------------------------------------------#


#-------------------------------------------------------#
#Merge [Arkadiyt]
pushd "${TMPDIR}" &>/dev/null
 #Merge [Inscope]
  if [[ -s "${HF_REPO_LOCAL}/DATA/arkadiyt/bugcrowd_all_domains_inscope.txt" ]] &&\
     [[ -s "${HF_REPO_LOCAL}/DATA/arkadiyt/hackerone_all_domains_inscope.txt" ]] &&\
     [[ -s "${HF_REPO_LOCAL}/DATA/arkadiyt/intigriti_all_domains_inscope.txt" ]]; then
    cat "${HF_REPO_LOCAL}/DATA/arkadiyt/bugcrowd_all_domains_inscope.txt" \
      "${HF_REPO_LOCAL}/DATA/arkadiyt/hackerone_all_domains_inscope.txt" \
      "${HF_REPO_LOCAL}/DATA/arkadiyt/intigriti_all_domains_inscope.txt" |\
      sort -u -o "${HF_REPO_LOCAL}/DATA/arkadiyt/all_domains_inscope.txt"
      cleanup_domains "${HF_REPO_LOCAL}/DATA/arkadiyt/all_domains_inscope.txt"
  fi
 #Merge [BBP]
  if [[ -s "${HF_REPO_LOCAL}/DATA/arkadiyt/bugcrowd_all_domains_bbp.txt" ]] &&\
     [[ -s "${HF_REPO_LOCAL}/DATA/arkadiyt/hackerone_all_domains_bbp.txt" ]] &&\
     [[ -s "${HF_REPO_LOCAL}/DATA/arkadiyt/intigriti_all_domains_bbp.txt" ]]; then
    cat "${HF_REPO_LOCAL}/DATA/arkadiyt/bugcrowd_all_domains_bbp.txt" \
      "${HF_REPO_LOCAL}/DATA/arkadiyt/hackerone_all_domains_bbp.txt" \
      "${HF_REPO_LOCAL}/DATA/arkadiyt/intigriti_all_domains_bbp.txt" |\
      sort -u -o "${HF_REPO_LOCAL}/DATA/arkadiyt/all_domains_bbp.txt"
      cleanup_domains "${HF_REPO_LOCAL}/DATA/arkadiyt/all_domains_bbp.txt"
  fi
 #Merge [VDP]
  if [[ -s "${HF_REPO_LOCAL}/DATA/arkadiyt/bugcrowd_all_domains_vdp.txt" ]] &&\
     [[ -s "${HF_REPO_LOCAL}/DATA/arkadiyt/hackerone_all_domains_vdp.txt" ]] &&\
     [[ -s "${HF_REPO_LOCAL}/DATA/arkadiyt/intigriti_all_domains_vdp.txt" ]]; then
    cat "${HF_REPO_LOCAL}/DATA/arkadiyt/bugcrowd_all_domains_vdp.txt" \
      "${HF_REPO_LOCAL}/DATA/arkadiyt/hackerone_all_domains_vdp.txt" \
      "${HF_REPO_LOCAL}/DATA/arkadiyt/intigriti_all_domains_vdp.txt" |\
      sort -u -o "${HF_REPO_LOCAL}/DATA/arkadiyt/all_domains_vdp.txt"
      cleanup_domains "${HF_REPO_LOCAL}/DATA/arkadiyt/all_domains_vdp.txt"
  fi
 #Merge [Wildcards]
  find "${HF_REPO_LOCAL}/DATA/arkadiyt" -type f -iname "*_inscope_wildcards*" -exec cat "{}" \; |\
   sort -u -o "${HF_REPO_LOCAL}/DATA/arkadiyt/all_domains_wildcards.txt"
   cleanup_domains "${HF_REPO_LOCAL}/DATA/arkadiyt/all_domains_wildcards.txt"
pushd "${TMPDIR}" &>/dev/null
#-------------------------------------------------------#


#-------------------------------------------------------#
#Merge [rix4uni]
pushd "${TMPDIR}" &>/dev/null
 #Merge [Inscope]
  if [[ -s "${HF_REPO_LOCAL}/DATA/rix4uni/bugcrowd_inscope.txt" ]] &&\
     [[ -s "${HF_REPO_LOCAL}/DATA/rix4uni/hackerone_inscope.txt" ]] &&\
     [[ -s "${HF_REPO_LOCAL}/DATA/rix4uni/intigriti_inscope.txt" ]] &&\
     [[ -s "${HF_REPO_LOCAL}/DATA/rix4uni/yeswehack_inscope.txt" ]]; then
    cat "${HF_REPO_LOCAL}/DATA/rix4uni/bugcrowd_inscope.txt" \
      "${HF_REPO_LOCAL}/DATA/rix4uni/hackerone_inscope.txt" \
      "${HF_REPO_LOCAL}/DATA/rix4uni/intigriti_inscope.txt" \
      "${HF_REPO_LOCAL}/DATA/rix4uni/yeswehack_inscope.txt" |\
      sort -u -o "${HF_REPO_LOCAL}/DATA/rix4uni/all_domains_inscope.txt"
      cleanup_domains "${HF_REPO_LOCAL}/DATA/rix4uni/all_domains_inscope.txt"
  fi
 #Merge [Wildcards]
  if [[ -s "${HF_REPO_LOCAL}/DATA/rix4uni/inscope_wildcards.txt" ]]; then
    cat "${HF_REPO_LOCAL}/DATA/rix4uni/inscope_wildcards.txt" |\
      sort -u -o "${HF_REPO_LOCAL}/DATA/rix4uni/all_domains_wildcards.txt"
      cleanup_domains "${HF_REPO_LOCAL}/DATA/rix4uni/all_domains_wildcards.txt"
  fi
pushd "${TMPDIR}" &>/dev/null
#-------------------------------------------------------#


#-------------------------------------------------------#
#Upload
pushd "${TMPDIR}" &>/dev/null
 find "${HF_REPO_LOCAL}/DATA/" -type f -size -3c -print -delete \; 2>/dev/null
 tree "${HF_REPO_LOCAL}/DATA" || find "${HF_REPO_LOCAL}/DATA" | sort | awk -F/ '{indent=""; for (i=2; i<NF; i++) indent=indent " "; print (NF>1 ? indent "--> " $NF : $NF)}' ; echo -e "\n"
 realpath "${HF_REPO_LOCAL}/DATA/arkadiyt" && ls -sh "${HF_REPO_LOCAL}/DATA/arkadiyt" ; echo -e "\n"
 realpath "${HF_REPO_LOCAL}/DATA/rix4uni" && ls -sh "${HF_REPO_LOCAL}/DATA/rix4uni" ; echo -e "\n"
 echo "ARTIFACTS_PATH=${HF_REPO_LOCAL}/DATA" >> "${GITHUB_ENV}" 2>/dev/null
 sync_to_ghcr
 sync_to_hf
popd &>/dev/null
#-------------------------------------------------------#
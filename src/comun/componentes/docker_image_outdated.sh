# ¿Hay en Docker Hub una version nueva de una imagen que ya esta en este equipo? Compara su huella
# (la de la etiqueta, con una consulta HEAD que no cuenta para los limites de Docker Hub) con la de
# la descargada. Sin la imagen o sin respuesta: no (no se puede saber)
function docker_image_outdated() {
    local img=$1 repo tag token remote local_d
    repo=${img%%:*} tag=${img#*:}
    [[ "$repo" == */* ]] || repo=library/$repo
    local_d=$(dk image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$img" 2> /dev/null | sed -n 's/^[^@]*@//p' | head -1)
    [ -z "$local_d" ] && return 1
    token=$(curl -q --proto =https -fsS --max-time 15 "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$repo:pull" 2> /dev/null \
        | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["token"])' 2> /dev/null) || return 1
    remote=$(curl -q --proto =https -fsSI --max-time 15 -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json" \
        "https://registry-1.docker.io/v2/$repo/manifests/$tag" 2> /dev/null | tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: *//p' | head -1)
    [[ "$remote" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
    [ "$remote" != "$local_d" ]
}


###########################################################
# Dockerfile that builds a Project Zomboid Gameserver
###########################################################
FROM cm2network/steamcmd:root

ARG STEAM_BETA=legacy41

LABEL maintainer="daniel.carrasco@electrosoftcloud.com"

ENV STEAMAPPID=380870
ENV STEAMAPP=pz
ENV STEAMAPPDIR="${HOMEDIR}/${STEAMAPP}-dedicated"
# Fix for a new installation problem in the Steamcmd client
ENV HOME="${HOMEDIR}"

# Install required packages
RUN apt-get update \
  && apt-get install -y --no-install-recommends --no-install-suggests \
  dos2unix \
  ca-certificates \
  curl \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Generate locales to allow other languages in the PZ Server
# RUN sed -i 's/^# *\(es_ES.UTF-8\)/\1/' /etc/locale.gen \
RUN sed -i 's/^# *\(ja_JP.UTF-8\)/\1/' /etc/locale.gen \
  # Generate locale
  && locale-gen

# Download the Project Zomboid dedicated server app using the steamcmd app
# Set the entry point file permissions
RUN set -x \
  && if [ -n "${STEAM_BETA}" ]; then set -- -beta "${STEAM_BETA}"; else set --; fi \
  && mkdir -p "${STEAMAPPDIR}" \
  && chown -R "${USER}:${USER}" "${STEAMAPPDIR}" \
  && for attempt in 1 2 3 4 5; do \
    bash "${STEAMCMDDIR}/steamcmd.sh" +force_install_dir "${STEAMAPPDIR}" \
    +login anonymous \
    +app_update "${STEAMAPPID}" "$@" validate \
    +quit && break; \
    if [ "$attempt" = "5" ]; then exit 1; fi; \
    sleep 10; \
  done

# Copy the entry point file
COPY --chown=${USER}:${USER} scripts/entry.sh /server/scripts/entry.sh
RUN chmod 550 /server/scripts/entry.sh

# Copy searchfolder file
COPY --chown=${USER}:${USER} scripts/search_folder.sh /server/scripts/search_folder.sh
RUN chmod 550 /server/scripts/search_folder.sh

# Copy apply_no_mo_culling.sh file
COPY --chown=${USER}:${USER} scripts/apply_no_mo_culling.sh /server/scripts/apply_no_mo_culling.sh
RUN chmod 550 /server/scripts/apply_no_mo_culling.sh

# Create required folders to keep their permissions on mount
RUN mkdir -p "${HOMEDIR}/Zomboid"

WORKDIR ${HOMEDIR}
# Expose ports
EXPOSE 16261-16262/udp \
  27015/tcp

ENTRYPOINT ["/server/scripts/entry.sh"]

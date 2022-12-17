#!/bin/bash
set -xu

# maximal number of log folders in the git repo
# 3 times / day * 4 days
MAX_LOG_DIRS=12
# maximal git history length
MAX_GIT_HISTORY_LEN=5

# all containers we going to grep for (fail|error)
REGULAR_CONTAINERS=(\
	# Rialto PoA nodes
	deployments_poa-node-arthur_1 \
	#deployments_poa-node-bertha_1 \
	#deployments_poa-node-carlos_1 \
	# Rialto nodes
	deployments_rialto-node-alice_1 \
	#deployments_rialto-node-bob_1 \
	#deployments_rialto-node-charlie_1 \
	#deployments_rialto-node-dave_1 \
	#deployments_rialto-node-eve_1 \
	# Rialto parachain nodes
	deployments_rialto-parachain-collator-alice_1 \
	#deployments_rialto-parachain-collator-bob_1 \
	#deployments_rialto-parachain-collator-charlie_1 \
	# Millau nodes
	deployments_millau-node-alice_1 \
	#deployments_millau-node-bob_1 \
	#deployments_millau-node-charlie_1 \
	#deployments_millau-node-dave_1 \
	#deployments_millau-node-eve_1 \

	# Auxiliary containers
	deployments_rialto-chainspec-exporter_1 \
	deployments_rialto-parachain-registrar_1 \

	# Rialto PoA <> Rialto bridge containers
	deployments_relay-headers-poa-to-rialto_1 \
	deployments_relay-poa-exchange-rialto_1 \
	deployments_relay-headers-rialto-to-poa_1 \
	deployments_poa-exchange-tx-generator_1 \

	# Rialto <> Millau bridge containers
	deployments_relay-millau-rialto_1 \
	deployments_relay-messages-millau-to-rialto-lane-00000001_1 \
	deployments_relay-messages-millau-to-rialto-generator_1 \
	deployments_relay-messages-millau-to-rialto-resubmitter_1 \
	deployments_relay-messages-rialto-to-millau-lane-00000001_1 \
	deployments_relay-messages-rialto-to-millau-generator_1 \
	deployments_relay-messages-millau-to-rialto-resubmitter_1 \

	# Westend > Millau bridge containers
	deployments_relay-headers-westend-to-millau-1_1 \
	deployments_relay-headers-westend-to-millau-2_1 \

	# RialtoParachain <> Millau bridge containers
	deployments_relay-messages-millau-to-rialto-parachain-generator_1 \
	deployments_relay-messages-rialto-parachain-to-millau-generator_1 \
	deployments_relay-millau-rialto-parachain_1 \
)

# rignt now in test deployments we only generate token swaps that are assumed to be successfully completed
# => we'll grep this container for (fail|error|cancel)
TOKEN_SWAP_GENERATOR_CONTAINER=(\
	deployments_relay-token-swap-generator_1 \
)

# all containers
CONTAINER_NAMES=("REGULAR_CONTAINERS" "TOKEN_SWAP_GENERATOR_CONTAINER")

# create a separate dir for logs
DATE=$(date +"%Y-%m-%d-%T")
LOGS_DIR="${DATE//:/-}-logs"
mkdir $LOGS_DIR
cd $LOGS_DIR

# dump container logs && grep for errors
dump_logs () {
	REGEX=$1
	shift
	for CONTAINER in "$@"
	do
		if [[ `docker ps -a | grep $CONTAINER | wc -l` -ne 0 ]]
		then
			SHORT_NAME="${CONTAINER//deployments_/}"
			docker logs $CONTAINER &> $SHORT_NAME.log
			grep -C 10 -Eiw $REGEX $SHORT_NAME.log &> $SHORT_NAME.errs
			# if there are no any errors, delete errs file
			[[ ! -s $SHORT_NAME.errs ]] && 'rm' -f $SHORT_NAME.errs
		fi
	done
}
dump_logs "(fail|error)" "${REGULAR_CONTAINERS[@]}"
dump_logs "(fail|error|cancel)" "${TOKEN_SWAP_GENERATOR_CONTAINER[@]}"
tar cvjf $LOGS_DIR.tar.bz2 $( find -name "*.log" )
rm *.log

# if there are no *.errs file in the logs directory, we may safely delete it
cd ..
[[ `ls -1 $LOGS_DIR/*.errs | wc -l` -eq 0 ]] && rm -rf $LOGS_DIR

# if log folder exists, git add it
if [[ -d $LOGS_DIR ]]
then
	git add $LOGS_DIR
	git commit -m "Added $LOGS_DIR"

	# if there are too many log folders, delete oldest
	LOG_DIRS=($(ls -1d *-logs))
	while [[ ${#LOG_DIRS[@]} -gt $MAX_LOG_DIRS ]]
	do
		OLDEST_LOGS_DIR=${LOG_DIRS[0]}
		git rm -r "$OLDEST_LOGS_DIR/"
		git commit -m "Removed $OLDEST_LOGS_DIR"
		rm -rf "$OLDEST_LOGS_DIR"
		LOG_DIRS=($(ls -1d *-logs))
	done

	# clean git history
	if [[ `git rev-list --count HEAD` -gt $MAX_GIT_HISTORY_LEN ]]
	then
		OLDEST_COMMIT_TO_KEEP=`git rev-parse HEAD~$MAX_GIT_HISTORY_LEN`
		git checkout --orphan temp $OLDEST_COMMIT_TO_KEEP
		git commit -m "Truncated history on $DATE"
		git rebase --onto temp $OLDEST_COMMIT_TO_KEEP master
		git branch -D temp
	fi

	git push -f
fi

#' flume: A package for modelling FLUvial Meta-Ecosystems
#'
#' Implementation of a theoretical/mechanistic model for exploring fluvial meta-ecosystems.
#'
#' @section Key functions:
#'
#' * [metacommunity()] Create species pools and associated attributes
#' * [river_network()] Build a river network object
#' * [flume()] Creates a model
#' * [run_simulation()] Runs the simulation
#'
#' @docType package
#' @name flume_package
NULL


#' Create a FLUvial Meta-Ecosystem model
#'
#' @param comm A [metacommunity()]
#' @param network A [river_network()]
#' @param dt The time step for the model, in the same time units as all fluxes
#'
#' @return An S3 object of class 'flume'
#' @export
flume = function(comm, network, dt) {
	structure(list(metacom = comm, networks = list(network), dt = dt), class="flume")
}


#' Compute network-wide occupancy from a simulation
occupancy_network = function(x) {
	rn = x[['networks']]
	res = data.table::rbindlist(lapply(rn, function(r){
		S = site_by_species(r, history = TRUE)
		data.table::rbindlist(lapply(S, function(s) {
			nm = colnames(s)
			if(is.null(nm))
				nm = as.character(1:ncol(s))
			data.table::data.table(species = nm, occupancy = colMeans(s))
			}), idcol = "time")
	}), idcol = "sim")
}

#' Run the simulation for a specified number of time steps
#'
#' This function begins with the current state of `x`, runs the model for `nt` steps,
#' then returns a copy of `x` with the updated state and state history.
#'
#' @param x A [flume()] object
#' @param nt The number of time steps
#' @param reps The number of replicate simulations to run; by default a single sim is run
#' on a new flume; for continuing simulations, the same number of replicates will be used
#' @return A modified copy of `x`, with state updated with the results of the simulation.
#' @export
run_simulation = function(x, nt, reps, parallel = TRUE, cores = parallel::detectCores()) {

	if(nt < 1)
		stop("at least one time step is required")

	if(missing(reps))
		reps = length(x[['networks']])

	# normally flumes are initialized with only a single river network
	# if more reps are desired, duplicate them
	if(reps > 1 && length(x[['networks']]) == 1)
		x[['networks']] = lapply(1:reps, function(i) x[['networks']][[1]])

	if(reps != length(x[['networks']]))
		warning("'reps' was specified, but it is not equal to the number of existing sims in 'x'\n",
				"'reps' will be ignored and the number of simulations will be equal to length(x$networks) (",
				length(x$networks), ")")

	if(parallel && reps > 1 && cores > 1) {
		x[['networks']] = parallel::mclapply(x[['networks']], .do_sim, comm = x[['metacom']], dt = x[['dt']],
				nt = nt, mc.cores = cores)
	} else {
		x[['networks']] = lapply(x[['networks']], .do_sim, comm = x[['metacom']], dt = x[['dt']], nt = nt)
	}

	return(x)
}


#' Worker function for running simulations in parallel
#' @param network A river network
#' @param comm A metacommunity
#' @param dt The size of the time step
#' @param nt The number of time steps
#' @return A modified copy of `network` with the results of the simulation
#' @keywords internal
.do_sim = function(network, comm, dt, nt) {
	R = state(network)
	S = site_by_species(network)

	for(tstep in 1:nt) {
		cp = col_prob(comm, network, dt = dt)
		ep = ext_prob(comm, network, dt = dt)
		dR = dRdt(comm, network)

		# no cols where already present, no exts where already absent
		cp[S == 1] = 0
		ep[S == 0] = 0
		cols = matrix(rbinom(length(cp), 1, cp), nrow=nrow(cp))
		exts = matrix(rbinom(length(ep), 1, ep), nrow=nrow(ep))
		S[cols == 1] = 1
		S[exts == 1] = 0

		## euler integration for now
		R = R + dR * dt

		site_by_species(network) = S
		state(network) = R
	}
	return(network)
}

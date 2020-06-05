"""
Implementations of pure, extended and unscented Kalman filters.

Algorithms based on Ch.5 of Bayesian Filtering & Smoothing (Särkka, 2014)

Wouter Kouw
04-06-2020
"""

using Distributions
using Random

function kalman_filter(observations,
                       transition_matrix,
                       emission_matrix,
                       process_noise,
                       measurement_noise,
                       state0)
    """
    Kalman filter (Th. 4.2)

    This filter is built for a linear Gaussian dynamical system with known
    transition coefficients, process and measurement noise.
    """

    # Dimensionality
    Dx = size(process_noise,1)
    Dy = size(measurement_noise,1)

    # Recast process noise to matrix
    if Dx == 1
        if typeof(process_noise) != Array{Float64,2}
            process_noise = reshape([process_noise], 1, 1)
        end
        if typeof(measurement_noise) != Array{Float64,2}
            measurement_noise = reshape([measurement_noise], 1, 1)
        end
    end

    # Time horizon
    time_horizon = length(observations)

    # Initialize estimate arrays
    mx = zeros(Dx, time_horizon)
    Px = zeros(Dx, Dx, time_horizon)

    # Initial state prior
    m_0, P_0 = state0

    # Start previous state variable
    m_tmin = m_0
    P_tmin = P_0

    for t = 1:time_horizon

        # Prediction step
        m_t_pred = transition_matrix*m_tmin
        P_t_pred = transition_matrix*P_tmin*transition_matrix' .+ process_noise

        # Update step
        v_t = observations[:,t] .- emission_matrix*m_t_pred
        S_t = emission_matrix*P_t_pred*emission_matrix' .+ measurement_noise
        K_t = P_t_pred*emission_matrix'*inv(S_t)
        m_t = m_t_pred .+ K_t*v_t
        P_t = P_t_pred .- K_t*S_t*K_t'

        # Store estimates
        mx[:,t] = m_t
        Px[:,:,t] = P_t

        # Update previous state variable
        m_tmin = m_t
        P_tmin = P_t
    end
    return mx, Px
end

function extended_kalman_filter(observations)
    """
    Extended Kalman filter with additive noise (Alg. 5.4)

    This filter is built for a linear Gaussian dynamical system with known
    transition coefficients, process and measurement noise.
    """

    # Time horizon
    time_horizon = length(observations)

    return
end

function unscented_kalman_filter(observations::Array{Float64,2},
                                 transition_function::Function,
                                 emission_function::Function,
                                 process_noise::Array{Float64,2},
                                 measurement_noise::Array{Float64,2},
                                 state0::Tuple{Array{Float64,1}, Array{Float64,2}};
                                 α=1.1, β=2., κ=.1)
    """
    Unscented Kalman filter with additive noise (Alg. 5.14)

    This filter is built for a linear Gaussian dynamical system with unknown
    transition function, but with known process and measurement noise.
    """

    # Dimensionality
    Dx = size(process_noise,1)
    Dy = size(measurement_noise,1)

    # Recast process noise to matrix
    if Dx == 1
        if typeof(process_noise) != Array{Float64,2}
            process_noise = reshape([process_noise], 1, 1)
        end
        if typeof(measurement_noise) != Array{Float64,2}
            measurement_noise = reshape([measurement_noise], 1, 1)
        end
    end

    # Time horizon
    time_horizon = length(observations)

    # Set algorithm parameters
    λ = α^2*(Dx + κ) - Dx

    if λ < 0
        error("Unsuitable algorithm parameters chosen; λ is negative.")
    end

    # Compute constant weights
    weights_m = [[λ/(Dx + λ)]; repeat( [1/(2*(Dx + λ))], 2*Dx)]
    weights_c = [[λ/(Dx + λ) + (1-α^2+β)]; repeat( [1/(2*(Dx + λ))], 2*Dx)]

    if sum(weights_m) != 1.0
        error("Unsuitable algorithm parameters chosen; first-order weights do not sum to 1.")
    end

    # Initialize estimate arrays
    mx = zeros(Dx, time_horizon)
    Px = zeros(Dx, Dx, time_horizon)

    # Initial state prior
    m_0, P_0 = state0

    # Start previous state variable
    m_tmin = m_0
    P_tmin = P_0

    for t = 1:time_horizon

        "Prediction step"

        # Square root of previous covariance matrix
        sP_tmin = sqrt(P_tmin)

        # Initialize sigma point array
        ξ = zeros(Dx, 2*Dx+1)

        # Center point
        ξ[:, 1] = m_tmin

        # Positive and negative spread points
        for i = 1:Dx
            ξ[:, 1+i] = m_tmin + sqrt(Dx + λ)*sP_tmin[:,i]
            ξ[:, 1+Dx+i] = m_tmin - sqrt(Dx + λ)*sP_tmin[:,i]
        end

        # Propagate sigma points through transition function
        ζ = transition_function.(ξ)

        # Compute predicted mean
        m_t_pred = zeros(Dx,)
        for i=1:2Dx+1
            m_t_pred += weights_m[i] .* ζ[:,i]
        end

        # Compute predicted covariance
        P_t_pred = zeros(Dx,Dx)
        for i = 1:2*Dx+1
            P_t_pred += weights_c[i]*(ζ[:,i] .- m_t_pred)*(ζ[:,i] .- m_t_pred)' .+ process_noise
        end

        "Update step"

        # Square root of previous covariance matrix
        sP_t_pred = sqrt(P_t_pred)

        # Initialize sigma point array
        ξ_ = zeros(Dx, 2*Dx+1)

        # Center point
        ξ_[:, 1] = m_t_pred

        # Positive and negative spread points
        for i = 1:Dx
            ξ_[:, 1+i] = m_t_pred + sqrt(Dx + λ)*sP_t_pred[:,i]
            ξ_[:, 1+Dx+i] = m_t_pred - sqrt(Dx + λ)*sP_t_pred[:,i]
        end

        # Propagate sigma points through emission function
        ζ_ = emission_function.(ξ_)

        # Compute mean of inverted likelihood
        μ_t = zeros(Dx,)
        for i = 1:2*Dx+1
            μ_t += weights_m[i] * ζ_[:,i]
        end

        # Compute covariance and cross-covariance of inverted likelihood
        S_t = zeros(Dx,Dx)
        C_t = zeros(Dx,Dx)
        for i = 1:2*Dx+1
            S_t += weights_c[i]*(ζ_[:,i] - μ_t)*(ζ_[:,i] - μ_t)' .+ measurement_noise
            C_t += weights_c[i]*(ξ_[:,i] - m_t_pred)*(ζ_[:,i] - μ_t)'
        end

        # Compute Kalman gain
        K_t = C_t*inv(S_t)

        # Compute filtered state parameters
        m_t = m_t_pred .+ K_t*(observations[:,t] - μ_t)
        P_t = P_t_pred .- K_t*S_t*K_t'

        # Store estimates
        mx[:,t] = m_t
        Px[:,:,t] = P_t

        # Update previous state variable
        m_tmin = m_t
        P_tmin = P_t
    end
    return mx, Px
end

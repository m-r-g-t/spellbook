{% set blockchain = 'ethereum' %}

{{config(
    schema = 'labels',
    alias = 'balancer_cowswap_amm_pools_' + blockchain,
    materialized = 'table',
    file_format = 'delta'
    )
}}

WITH events AS (
    -- binds
    SELECT call_block_number AS block_number,
           contract_address  AS pool,
           token,
           denorm
    FROM {{ source('b_cow_amm_ethereum', 'BCoWPool_call_bind') }}
    WHERE call_success

    UNION all

    -- unbinds
    SELECT call_block_number AS block_number,
            contract_address AS pool,
            token,
            uint256 '0' AS denorm
    FROM {{ source('b_cow_amm_ethereum', 'BCoWPool_call_unbind') }}
    WHERE call_success
),

state_with_gaps AS (
    SELECT events.block_number
           , events.pool
           , events.token
           , CAST(events.denorm AS uint256) AS denorm,
    LEAD(events.block_number, 1, 99999999) OVER (PARTITION BY events.pool, events.token ORDER BY events.block_number) AS next_block_number
    FROM events
),

settings AS (
    SELECT pool,
        coalesce(t.symbol,'?') AS symbol,
        denorm,
        next_block_number
    FROM state_with_gaps s
    LEFT JOIN {{ source('tokens', 'erc20') }} t ON s.token = t.contract_address
        AND t.blockchain = '{{blockchain}}'
    WHERE next_block_number = 99999999
        AND denorm > uint256 '0'
),

final AS (
    SELECT
      '{{blockchain}}' AS blockchain,
      pool AS address,
      CONCAT('BCowAMM: ', array_join(array_agg(symbol), '/')) AS name,
      'Balancer CoWSwap AMM' AS pool_type,
      'balancer_cowswap_amm_pool' AS category,
      'balancerlabs' AS contributor,
      'query' AS source,
      timestamp '2024-07-20' AS created_at,
      now() AS updated_at,
      'balancer_cowswap_amm_pools_ethereum' AS model_name,
      'identifier' as label_type
    FROM   (
        SELECT s1.pool, symbol FROM settings s1
    ) s

    GROUP BY 1, 2
)

SELECT *
FROM final
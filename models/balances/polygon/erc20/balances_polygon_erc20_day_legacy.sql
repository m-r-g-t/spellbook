{{ config(
        schema = 'balances_polygon_erc20',
        tags = ['legacy'],
        alias = alias('erc20_day', legacy_model=True)
        )
}}

SELECT 
1 AS DUMMY 
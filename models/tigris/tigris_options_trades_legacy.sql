{{ config(
	tags=['legacy'],
	
        alias = alias('options_trades', legacy_model=True)
        )
}}

SELECT 
    1 as dummy
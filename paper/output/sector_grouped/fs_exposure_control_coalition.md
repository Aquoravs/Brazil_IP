# First Stage — With Exposure Control (cycle-specific, muni×year FE, coalition)

                                               M+G             M+G+P
Dependent Var.:                        delta_s_mjt       delta_s_mjt
                                                                    
Z_mayor_coalition_cycle_specific          0.0193**          0.0185**
                                         (0.0074)          (0.0077) 
Z_gov_coalition_cycle_specific           -0.0023           -0.0027  
                                         (0.0122)          (0.0113) 
exposure_control_cycle_specific          -0.0138*          -0.0138* 
                                         (0.0065)          (0.0065) 
Z_pres_coalition_cycle_specific                            -0.0043  
                                                           (0.0143) 
Fixed-Effects:                         -----------       -----------
muni_id-sector_group                           Yes               Yes
muni_id-year                                   Yes               Yes
________________________________       ___________       ___________
S.E.: Clustered                  by: muni. & sect. by: muni. & sect.
Observations                               700,650           700,650
R2                                         0.06238           0.06238
---
Signif. codes: 0 '***' 0.01 '**' 0.05 '*' 0.1 ' ' 1

# Levels First Stage — Single Tiers (cycle-specific, muni×year FE, coalition)

                                                Mayor          Governor
Dependent Var.:                                 s_mjt             s_mjt
                                                                       
Zlev_mayor_coalition_cycle_specific           0.2385                   
                                             (0.1359)                  
Zlev_gov_coalition_cycle_specific                               0.2725*
                                                               (0.1464)
Zlev_pres_coalition_cycle_specific                                     
                                                                       
Fixed-Effects:                               --------          --------
muni_id-sector_group                              Yes               Yes
muni_id-year                                      Yes               Yes
___________________________________          ________          ________
S.E.: Clustered                     by: muni. & sect. by: muni. & sect.
Observations                                  700,650           700,650
R2                                            0.35935           0.36016

                                            President
Dependent Var.:                                 s_mjt
                                                     
Zlev_mayor_coalition_cycle_specific                  
                                                     
Zlev_gov_coalition_cycle_specific                    
                                                     
Zlev_pres_coalition_cycle_specific          0.3673***
                                           (0.0915)  
Fixed-Effects:                             ----------
muni_id-sector_group                              Yes
muni_id-year                                      Yes
___________________________________        __________
S.E.: Clustered                     by: muni. & sect.
Observations                                  700,650
R2                                            0.36013
---
Signif. codes: 0 '***' 0.01 '**' 0.05 '*' 0.1 ' ' 1

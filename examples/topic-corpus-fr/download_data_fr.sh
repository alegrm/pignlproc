#!/bin/sh

WORKSPACE=../../workspace
DBPEDIA_36_EN=http://downloads.dbpedia.org/3.6/en
DBPEDIA_36_FR=http://downloads.dbpedia.org/3.6/fr

(cd $WORKSPACE && wget -c $DBPEDIA_36_EN/article_categories_en.nt.bz2)
(cd $WORKSPACE && wget -c $DBPEDIA_36_EN/skos_categories_en.nt.bz2)
(cd $WORKSPACE && wget -c $DBPEDIA_36_FR/long_abstracts_fr.nt.bz2)


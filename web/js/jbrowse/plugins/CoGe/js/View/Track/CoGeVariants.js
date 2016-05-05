/**
 * Sub-class of HTMLFeatures that adds CoGe-specific features.
 * Added by mdb 1/15/2014
 */

var coge_variants;
define( [
             'dojo/_base/declare',
             'dijit/Dialog',
            'JBrowse/View/Track/HTMLFeatures'
         ],

         function(
             declare,
             Dialog,
             HTMLFeatures
         ) {
return declare( [ HTMLFeatures ], {
    constructor: function() {
        this.inherited(arguments); // call superclass constructor
        coge_variants = this;
        this.browser = arguments[0].browser;
    },

    // ----------------------------------------------------------------

    _create_features_search_dialog: function(track) {
        this._track = track;
        var content = '<div id="coge-track-search-dialog"><table><tr><tr><td>Chromosome:</td><td>';
        content += coge.build_chromosome_select('Any');
        content += '</td></tr><tr><td style="vertical-align:top;">Features:</td><td id="coge_search_features">';
        content += coge.build_features_checkboxes();
        content += '</td></tr></table>';
        content += '<div class="dijitDialogPaneActionBar"><button data-dojo-type="dijit/form/Button" type="button" onClick="coge_variants._search_features()">OK</button><button data-dojo-type="dijit/form/Button" type="button" onClick="coge_variants._search_dialog.hide()">Cancel</button></div></div>';
        this._search_dialog = new Dialog({
            title: "Find SNPs in Features",
            content: content,
            onHide: function() {
                this.destroyRecursive();
                coge_variants._search_dialog = null;
            },
            style: "width: 300px"
        });
        this._search_dialog.show();
    },

    // ----------------------------------------------------------------

    _create_types_search_dialog: function(track) {
        this._track = track;
        var content = '<div id="coge-track-search-dialog"><table><tr><tr><td>Chromosome:</td><td>';
        content += coge.build_chromosome_select('Any');
        content += '</td></tr><tr><td style="vertical-align:top;">SNPs:</td><td id="coge_search_types">';
        ['A>C','A>G','A>T','C>A','C>G','C>T','G>A','G>C','G>T','T>A','T>C','T>G','deletion','insertion'].forEach(function(t) {
            content += '<div><input name="type" type="checkbox"> <label>' + t + '</label></div>';
        });
        content += '</td></tr></table>';
        content += '<div class="dijitDialogPaneActionBar"><button data-dojo-type="dijit/form/Button" type="button" onClick="coge_variants._search_types()">OK</button><button data-dojo-type="dijit/form/Button" type="button" onClick="coge_variants._search_dialog.hide()">Cancel</button></div></div>';
        this._search_dialog = new Dialog({
            title: "Find types of SNPs",
            content: content,
            onHide: function() {
                this.destroyRecursive();
                coge_variants._search_dialog = null;
            },
            style: "width: 300px"
        });
        this._search_dialog.show();
    },

    // ----------------------------------------------------------------

    _exportFormats: function() {
        return [
            {name: 'GFF3', label: 'GFF3', fileExt: 'gff3'},
            {name: 'BED', label: 'BED', fileExt: 'bed'},
            { name: 'SequinTable', label: 'Sequin Table', fileExt: 'sqn' },
        	{ name: 'VCF4.1', label: 'VCF', fileExt: 'vcf' }
        ];
    },

    // ----------------------------------------------------------------

	_search_features: function() {
        var types = coge.get_checked_values('coge_search_features', 'feature types', true);
        if (!types)
            return;
		var ref_seq = dojo.byId('coge_ref_seq');
		var chr = ref_seq.options[ref_seq.selectedIndex].innerHTML;
		var div = dojo.byId('coge-track-search-dialog');
		dojo.empty(div);
		div.innerHTML = '<img src="picts/ajax-loader.gif">';
		var search = {type: 'SNPs', chr: chr, features: types};
        this._track.config.coge.search = search;
		var eid = this._track.config.coge.id;
    	var url = api_base_url + '/experiment/' + eid + '/snps/' + chr + '?features=' + search.features;
    	dojo.xhrGet({
    		url: url,
    		handleAs: 'json',
	  		load: dojo.hitch(this, function(data) {
                if (this._search_dialog)
	  				this._search_dialog.hide();
	  			if (data.error) {
	  				coge.error('Search', data);
	  				return;
	  			}
	  			if (data.length == 0) {
	  				coge.error('Search', 'no SNPs found');
	  				return;
	  			}
	  			coge.new_search_track(this._track, data);
    		}),
    		error: dojo.hitch(this, function(data) {
    			if (this._search_dialog)
	  				this._search_dialog.hide();
	  			coge.error('Search', data);
    		})
    	})
    },

    // ----------------------------------------------------------------

    _search_types: function() {
        var types = coge.get_checked_values('coge_search_types', 'SNP types');
        if (!types)
            return;
        var ref_seq = dojo.byId('coge_ref_seq');
        var chr = ref_seq.options[ref_seq.selectedIndex].innerHTML;
        var div = dojo.byId('coge-track-search-dialog');
        dojo.empty(div);
        div.innerHTML = '<img src="picts/ajax-loader.gif">';
        var search = {type: 'SNPs', chr: chr, snp_type: types};
        this._track.config.coge.search = search;
        var eid = this._track.config.coge.id;
        var url = api_base_url + '/experiment/' + eid + '/snps/' + chr + '?snp_type=' + types.replace(new RegExp('>', 'g'), '-');
        dojo.xhrGet({
            url: url,
            handleAs: 'json',
            load: dojo.hitch(this, function(data) {
                if (this._search_dialog)
	  				this._search_dialog.hide();
                if (data.error) {
                    coge.error('Search', data);
                    return;
                }
                if (data.length == 0) {
                    coge.error('Search', 'no SNPs found');
                    return;
                }
                coge.new_search_track(this._track, data);
            }),
            error: dojo.hitch(this, function(data) {
                if (this._search_dialog)
	  				this._search_dialog.hide();
                coge.error('Search', data);
            })
        })
    },

    // ----------------------------------------------------------------

    _trackMenuOptions: function() {
        var options = this.inherited(arguments);
        var track = this;

        if (track.config.coge.type == 'notebook')
            return options;

        if (!track.config.coge.search_track)  {
	        options.push({
                label: 'Find SNPs in Features',
                onClick: function(){coge_variants._create_features_search_dialog(track);}
            });
            options.push({
                label: 'Find types of SNPs',
                onClick: function(){coge_variants._create_types_search_dialog(track);}
            });
        }
        options.push({
            label: 'Download Track Data',
            onClick: function(){coge.create_download_dialog(track);}
        });
        return options;
    },

    // ----------------------------------------------------------------

    updateStaticElements: function( coords ) {
        this.inherited( arguments );
        coge.adjust_nav(this.config.coge.id)
    }
});
});
